import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../anime/data/anime_list_store.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/network/app_network_error.dart';
import '../data/anime_garden_download_coordinator.dart';
import '../data/anime_garden_repository.dart';
import 'anime_garden_episode_match_page.dart';

class AnimeGardenDownloadController extends GetxController {
  AnimeGardenDownloadController({
    required this.subject,
    AnimeGardenRepository? repository,
    AnimeGardenDownloadCoordinator? downloadCoordinator,
  }) : _repository = repository ?? AnimeGardenRepository(),
       _downloadCoordinator =
           downloadCoordinator ?? AnimeGardenDownloadCoordinator() {
    keywordController.text = subject.name;
  }

  final BangumiSubject subject;
  final AnimeGardenRepository _repository;
  final AnimeGardenDownloadCoordinator _downloadCoordinator;
  final keywordController = TextEditingController();
  final scrollController = ScrollController();
  final results = <AnimeGardenResource>[].obs;
  final filteredResults = <AnimeGardenResource>[].obs;
  final loading = false.obs;
  final loadingMore = false.obs;
  final hasMore = true.obs;
  final selectedResolutions = <String>{}.obs;
  final selectedCodecs = <String>{}.obs;
  final sizeRange = const RangeValues(0, 50).obs;
  final addingResourceIds = <int>{}.obs;
  int _page = 1;
  var _searchGeneration = 0;

  bool get addingAnime => addingResourceIds.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    search();
  }

  @override
  void onClose() {
    _searchGeneration++;
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    keywordController.dispose();
    super.onClose();
  }

  Future<void> search() async {
    final keyword = keywordController.text.trim();
    final generation = ++_searchGeneration;
    if (keyword.isEmpty) {
      results.clear();
      filteredResults.clear();
      hasMore.value = false;
      loading.value = false;
      await showErrorDialog(title: '无法检索', message: '请输入动漫名');
      return;
    }

    _page = 1;
    results.clear();
    filteredResults.clear();
    hasMore.value = true;
    loading.value = true;
    try {
      final result = await _repository.searchResources(keyword, page: _page);
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      results.assignAll(result.resources);
      _updateFilteredResults();
      hasMore.value = !result.complete;
      if (result.resources.isEmpty) {
        await showInfoDialog(title: '检索结果', message: '没有找到下载资源');
      }
    } catch (error) {
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      await showErrorDialog(title: '检索失败', message: errorMessageOf(error));
    } finally {
      if (generation == _searchGeneration && !isClosed) {
        loading.value = false;
      }
    }
  }

  Future<void> loadMore() async {
    if (loading.value || loadingMore.value || !hasMore.value) {
      return;
    }

    final keyword = keywordController.text.trim();
    if (keyword.isEmpty) {
      return;
    }

    loadingMore.value = true;
    final generation = _searchGeneration;
    try {
      final nextPage = _page + 1;
      final result = await _repository.searchResources(keyword, page: nextPage);
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      _page = nextPage;
      results.addAll(result.resources);
      _updateFilteredResults();
      hasMore.value = !result.complete;
    } catch (error) {
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      await showErrorDialog(title: '加载失败', message: errorMessageOf(error));
    } finally {
      if (generation == _searchGeneration && !isClosed) {
        loadingMore.value = false;
      }
    }
  }

  Future<void> addAnimeWithResource(AnimeGardenResource resource) async {
    if (addingAnime) {
      return;
    }

    addingResourceIds.add(resource.id);
    try {
      final context = await _downloadCoordinator.prepareEpisodeMatching(
        subject: subject,
        resource: resource,
      );
      await Get.to(
        () => AnimeGardenEpisodeMatchPage(
          subject: subject,
          resource: resource,
          files: context.files,
          bangumiEpisodes: context.bangumiEpisodes,
          animeListStore: Get.find<AnimeListStore>(),
        ),
      );
    } catch (error) {
      await showErrorDialog(title: '获取文件列表失败', message: errorMessageOf(error));
    } finally {
      addingResourceIds.remove(resource.id);
    }
  }

  void setSizeRange(RangeValues value) {
    sizeRange.value = value;
    _updateFilteredResults();
  }

  void toggleResolution(String value) {
    if (!selectedResolutions.remove(value)) {
      selectedResolutions.add(value);
    }
    _updateFilteredResults();
  }

  void toggleCodec(String value) {
    if (!selectedCodecs.remove(value)) {
      selectedCodecs.add(value);
    }
    _updateFilteredResults();
  }

  void _updateFilteredResults() {
    filteredResults.assignAll(
      results.where(
        (resource) =>
            _matchesSize(resource) &&
            _matchesResolution(resource) &&
            _matchesCodec(resource),
      ),
    );
  }

  bool _matchesSize(AnimeGardenResource resource) {
    if (resource.size <= 0) {
      return true;
    }
    final sizeGb = resource.size / 1024 / 1024;
    final range = sizeRange.value;
    return sizeGb >= range.start && sizeGb <= range.end;
  }

  bool _matchesResolution(AnimeGardenResource resource) {
    if (selectedResolutions.isEmpty) {
      return true;
    }
    final title = resource.normalizedTitle;
    return selectedResolutions.any((resolution) {
      return switch (resolution) {
        '1080p' => title.contains('1080p') || title.contains('1920x1080'),
        '2k' =>
          title.contains('2k') ||
              title.contains('1440p') ||
              title.contains('2560x1440'),
        '4k' =>
          title.contains('4k') ||
              title.contains('2160p') ||
              title.contains('3840x2160'),
        _ => false,
      };
    });
  }

  bool _matchesCodec(AnimeGardenResource resource) {
    if (selectedCodecs.isEmpty) {
      return true;
    }
    final title = resource.normalizedTitle;
    return selectedCodecs.any((codec) {
      return switch (codec) {
        'H.264/AVC' =>
          title.contains('h.264') ||
              title.contains('h264') ||
              title.contains('x264') ||
              title.contains('avc'),
        'H.265/HEVC' =>
          title.contains('h.265') ||
              title.contains('h265') ||
              title.contains('hevc') ||
              title.contains('x265'),
        'AV1' => title.contains('av1'),
        _ => false,
      };
    });
  }

  void _onScroll() {
    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      loadMore();
    }
  }
}
