import 'package:get/get.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../anime_garden/data/anime_garden_download_coordinator.dart';
import '../../anime_garden/presentation/anime_garden_bindings.dart';
import '../../anime_garden/presentation/anime_garden_episode_match_page.dart';
import '../../auth/presentation/current_user_controller.dart';
import '../../bangumi/data/airing_status.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../../subscriptions/data/subscription_models.dart';
import '../../subscriptions/data/subscription_service.dart';
import '../../subscriptions/data/subscription_store.dart';
import '../../subscriptions/presentation/subscription_editor_page.dart';
import '../data/anime_list_store.dart';
import '../data/anime_service.dart';

class AnimeDetailController extends GetxController {
  AnimeDetailController({
    required this.animeId,
    this.initialAnime,
    AnimeService? animeService,
    BangumiRepository? bangumiRepository,
    AnimeGardenDownloadCoordinator? downloadCoordinator,
    SubscriptionService? subscriptionService,
    SubscriptionStore? subscriptionStore,
    CurrentUserController? currentUserController,
  }) : _animeService = animeService ?? AnimeService(),
       _bangumiRepository = bangumiRepository ?? BangumiRepository(),
       _downloadCoordinator =
           downloadCoordinator ?? AnimeGardenDownloadCoordinator(),
       _subscriptionService = subscriptionService ?? SubscriptionService(),
       _subscriptionStore =
           subscriptionStore ?? SubscriptionStore(service: subscriptionService),
       _currentUser = currentUserController ?? CurrentUserController();

  final int animeId;
  final AnimeRead? initialAnime;
  final AnimeService _animeService;
  final BangumiRepository _bangumiRepository;
  final AnimeGardenDownloadCoordinator _downloadCoordinator;
  final SubscriptionService _subscriptionService;
  final SubscriptionStore _subscriptionStore;
  final CurrentUserController _currentUser;
  final anime = Rxn<AnimeRead>();
  final subscription = Rxn<SubscriptionRead>();
  final loading = true.obs;
  final deleting = false.obs;
  final refreshing = false.obs;
  final rematching = false.obs;

  @override
  void onInit() {
    super.onInit();
    anime.value = initialAnime;
    load();
  }

  Future<void> load() async {
    loading.value = true;
    try {
      final loadedAnime = await _animeService.getAnime(animeId);
      if (isClosed) return;
      anime.value = loadedAnime;
      await loadSubscription();
    } catch (error) {
      if (isClosed) return;
      if (anime.value == null) {
        await showErrorDialog(
          title: '详情加载失败',
          message: errorMessageOf(error),
          error: error,
        );
      }
    } finally {
      if (!isClosed) {
        loading.value = false;
      }
    }
  }

  /// Guest cannot create or edit subscriptions, so the entry point stays hidden
  /// for them instead of failing on save with a 403.
  bool get canSubscribe => _currentUser.canManageDownloads;

  Future<void> loadSubscription() async {
    final currentAnime = anime.value;
    if (currentAnime == null || !canSubscribe) return;
    // Refreshing the shared store also updates the home "追番中" section, so a
    // subscription saved here is visible there without a manual pull.
    await _subscriptionStore.refresh();
    if (isClosed) return;
    subscription.value = _subscriptionStore.forAnime(currentAnime.id);
  }

  /// Resolves the airing status, which decides whether the editor offers to
  /// backfill the episodes already broadcast.
  ///
  /// A failure is not worth blocking on: `unknown` only hides an optional
  /// switch.
  Future<AiringStatus> _airingStatus(AnimeRead currentAnime) async {
    try {
      final episodes = await _bangumiRepository.getMainEpisodes(
        currentAnime.bangumiId,
      );
      return deriveAiringStatus(
        airDate: currentAnime.airDate,
        episodes: episodes,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        '推导放送状态失败 anime=${currentAnime.id}',
        tag: 'Bangumi',
        error: error,
        stackTrace: stackTrace,
      );
      return AiringStatus.unknown;
    }
  }

  Future<void> openSubscriptionEditor() async {
    final currentAnime = anime.value;
    if (currentAnime == null || !canSubscribe) return;
    final status = await _airingStatus(currentAnime);
    if (isClosed) return;
    final result = await Get.to<bool>(
      () => SubscriptionEditorPage(
        bangumiId: currentAnime.bangumiId,
        title: currentAnime.displayName,
        subtitle: currentAnime.originalName,
        status: status,
        existing: subscription.value,
        service: _subscriptionService,
      ),
    );
    if (result == true && !isClosed) {
      await loadSubscription();
    }
  }

  Future<void> refreshAnime() async {
    final currentAnime = anime.value;
    if (currentAnime == null || refreshing.value) {
      return;
    }
    refreshing.value = true;
    try {
      final subject = await _bangumiRepository.getSubjectDetail(
        currentAnime.bangumiId,
      );
      final refreshedAnime = await _animeService.updateAnimeMetadata(
        animeId: currentAnime.id,
        subject: subject,
      );
      if (isClosed) return;
      anime.value = refreshedAnime;
      await showInfoDialog(title: '刷新成功', message: '番剧信息已从 Bangumi 更新到服务器');
    } catch (error) {
      if (isClosed) return;
      await showErrorDialog(
        title: '刷新失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (!isClosed) {
        refreshing.value = false;
      }
    }
  }

  Future<void> rematchEpisodes() async {
    final currentAnime = anime.value;
    if (currentAnime == null || rematching.value) {
      return;
    }
    final downloadHash = currentAnime.downloadHash;
    if (downloadHash == null || downloadHash.isEmpty) {
      await showErrorDialog(title: '无法重新匹配', message: '该番剧没有关联的下载种子');
      return;
    }

    rematching.value = true;
    try {
      final subject = currentAnime.toBangumiSubjectDetail();
      final context = await _downloadCoordinator.prepareEpisodeRematch(
        subject: subject,
        downloadHash: downloadHash,
      );
      if (isClosed) return;

      final animeListStore = Get.find<AnimeListStore>();
      Future<void> onSave(List<AnimeEpisodeCreate> episodes) =>
          _downloadCoordinator.submitRematchedEpisodes(
            animeId: currentAnime.id,
            downloadHash: downloadHash,
            episodes: episodes,
          );

      final result = await Get.to<bool>(
        () => AnimeGardenEpisodeMatchPage(
          subject: subject,
          files: context.files,
          bangumiEpisodes: context.bangumiEpisodes,
          existingEpisodes: currentAnime.episodes,
          animeListStore: animeListStore,
          onSave: onSave,
          pageTitle: '重新匹配 Episode',
        ),
        binding: AnimeGardenEpisodeMatchBinding(
          subject: subject,
          files: context.files,
          bangumiEpisodes: context.bangumiEpisodes,
          existingEpisodes: currentAnime.episodes,
          animeListStore: animeListStore,
          onSave: onSave,
        ),
      );
      if (result == true && !isClosed) {
        await load();
      }
    } catch (error) {
      if (isClosed) return;
      await showErrorDialog(
        title: '获取文件列表失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (!isClosed) {
        rematching.value = false;
      }
    }
  }

  Future<bool> deleteAnime({required bool deleteFiles}) async {
    final currentAnime = anime.value;
    if (currentAnime == null || deleting.value) {
      return false;
    }
    deleting.value = true;
    try {
      await _animeService.deleteAnime(
        currentAnime.id,
        deleteFiles: deleteFiles,
      );
      return true;
    } catch (error) {
      await showErrorDialog(
        title: '删除失败',
        message: errorMessageOf(error),
        error: error,
      );
      return false;
    } finally {
      if (!isClosed) {
        deleting.value = false;
      }
    }
  }
}
