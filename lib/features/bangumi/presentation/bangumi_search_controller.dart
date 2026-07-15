import 'dart:async';

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
  final results = <BangumiSubject>[].obs;
  final loading = false.obs;
  Timer? _debounce;
  var _searchGeneration = 0;

  Map<int, AnimeRead> get existingAnimeMap => animeListStore.animeMap;

  @override
  void onClose() {
    _searchGeneration++;
    _debounce?.cancel();
    queryController.dispose();
    super.onClose();
  }

  Future<void> search([String? value]) async {
    final keyword = (value ?? queryController.text).trim();
    final generation = ++_searchGeneration;
    if (keyword.isEmpty) {
      results.clear();
      loading.value = false;
      return;
    }

    loading.value = true;
    try {
      final subjects = await _repository.searchAnime(keyword);
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      results.assignAll(subjects);
      if (subjects.isEmpty) {
        await showInfoDialog(title: '搜索结果', message: '没有找到相关番剧');
      }
    } catch (error) {
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      await showErrorDialog(title: '搜索失败', message: errorMessageOf(error));
    } finally {
      if (generation == _searchGeneration && !isClosed) {
        loading.value = false;
      }
    }
  }
}
