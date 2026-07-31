import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../anime_garden/data/anime_garden_download_coordinator.dart';
import '../../anime_garden/presentation/anime_garden_bindings.dart';
import '../../anime_garden/presentation/anime_garden_episode_match_page.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../data/anime_list_store.dart';
import '../data/anime_service.dart';

class AnimeDetailController extends GetxController {
  AnimeDetailController({
    required this.animeId,
    this.initialAnime,
    AnimeService? animeService,
    BangumiRepository? bangumiRepository,
    AnimeGardenDownloadCoordinator? downloadCoordinator,
  }) : _animeService = animeService ?? AnimeService(),
       _bangumiRepository = bangumiRepository ?? BangumiRepository(),
       _downloadCoordinator =
           downloadCoordinator ?? AnimeGardenDownloadCoordinator();

  final int animeId;
  final AnimeRead? initialAnime;
  final AnimeService _animeService;
  final BangumiRepository _bangumiRepository;
  final AnimeGardenDownloadCoordinator _downloadCoordinator;
  final anime = Rxn<AnimeRead>();
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
