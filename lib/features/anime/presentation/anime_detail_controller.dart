import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../data/anime_service.dart';

class AnimeDetailController extends GetxController {
  AnimeDetailController({
    required this.animeId,
    this.initialAnime,
    AnimeService? animeService,
    BangumiRepository? bangumiRepository,
  }) : _animeService = animeService ?? AnimeService(),
       _bangumiRepository = bangumiRepository ?? BangumiRepository();

  final int animeId;
  final AnimeRead? initialAnime;
  final AnimeService _animeService;
  final BangumiRepository _bangumiRepository;
  final anime = Rxn<AnimeRead>();
  final loading = true.obs;
  final deleting = false.obs;
  final refreshing = false.obs;

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
