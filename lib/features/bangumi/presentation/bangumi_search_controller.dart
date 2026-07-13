import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../data/bangumi_repository.dart';

class BangumiSearchController extends GetxController {
  BangumiSearchController({BangumiRepository? repository})
    : _repository = repository ?? BangumiRepository();

  final BangumiRepository _repository;
  final queryController = TextEditingController();
  final results = <BangumiSubject>[].obs;
  final loading = false.obs;
  final message = RxnString();
  Timer? _debounce;
  var _searchGeneration = 0;

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
      message.value = null;
      return;
    }

    loading.value = true;
    message.value = null;
    try {
      final subjects = await _repository.searchAnime(keyword);
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      results.assignAll(subjects);
      if (subjects.isEmpty) {
        message.value = '没有找到相关番剧';
      }
    } catch (error) {
      if (generation != _searchGeneration || isClosed) {
        return;
      }
      message.value = '搜索失败\n${error.toString()}';
    } finally {
      if (generation == _searchGeneration && !isClosed) {
        loading.value = false;
      }
    }
  }
}
