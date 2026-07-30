import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../anime/data/anime_list_store.dart';
import '../../anime/data/anime_service.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/bangumi_repository.dart';

class BangumiSearchController extends GetxController {
  BangumiSearchController({
    required this.animeListStore,
    BangumiRepository? repository,
  }) : _repository = repository ?? BangumiRepository();

  final AnimeListStore animeListStore;
  final BangumiRepository _repository;
  final queryController = TextEditingController();
  final scrollController = ScrollController();
  final results = <BangumiSubject>[].obs;
  final loading = false.obs;
  final loadingMore = false.obs;
  final hasMore = false.obs;
  final total = 0.obs;
  final selectedTypes = <int>{2}.obs;
  var _searchGeneration = 0;
  var _nextOffset = 0;
  var _activeKeyword = '';
  var _activeFilter = const BangumiSearchFilter(types: [2]);

  static const _pageSize = 20;

  Map<int, AnimeRead> get existingAnimeMap => animeListStore.animeMap;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_handleScroll);
  }

  @override
  void onClose() {
    _searchGeneration++;
    queryController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  Future<void> search([String? value]) async {
    final keyword = (value ?? queryController.text).trim();
    final generation = ++_searchGeneration;
    if (keyword.isEmpty) {
      results.clear();
      loading.value = false;
      loadingMore.value = false;
      hasMore.value = false;
      total.value = 0;
      return;
    }

    final filter = _buildFilter();
    _activeKeyword = keyword;
    _activeFilter = filter;
    _nextOffset = 0;
    loading.value = true;
    hasMore.value = false;
    try {
      final page = await _repository.searchAnime(
        keyword: keyword,
        limit: _pageSize,
        filter: filter,
      );
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      results.assignAll(page.subjects);
      total.value = page.total;
      _nextOffset = page.nextOffset;
      hasMore.value = page.hasMore;
    } catch (error) {
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      await showErrorDialog(
        title: '搜索失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (generation == _searchGeneration && !isClosed) {
        loading.value = false;
      }
    }
  }

  Future<void> loadMore() async {
    if (loading.value ||
        loadingMore.value ||
        !hasMore.value ||
        _activeKeyword.isEmpty) {
      return;
    }

    final generation = _searchGeneration;
    loadingMore.value = true;
    try {
      final page = await _repository.searchAnime(
        keyword: _activeKeyword,
        limit: _pageSize,
        offset: _nextOffset,
        filter: _activeFilter,
      );
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      final existingIds = results.map((subject) => subject.id).toSet();
      results.addAll(
        page.subjects.where((subject) => existingIds.add(subject.id)),
      );
      total.value = page.total;
      _nextOffset = page.nextOffset;
      hasMore.value = page.hasMore && page.subjects.isNotEmpty;
    } catch (error) {
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      Get.snackbar('加载更多失败', errorMessageOf(error));
    } finally {
      if (generation == _searchGeneration && !isClosed) {
        loadingMore.value = false;
      }
    }
  }

  Future<void> applyFilters() =>
      search(_activeKeyword.isEmpty ? null : _activeKeyword);

  void toggleType(int type) {
    if (!selectedTypes.remove(type)) {
      selectedTypes.add(type);
    }
  }

  BangumiSearchFilter _buildFilter() {
    return BangumiSearchFilter(types: selectedTypes.toList()..sort());
  }

  void _handleScroll() {
    if (scrollController.position.extentAfter < 360) {
      loadMore();
    }
  }
}
