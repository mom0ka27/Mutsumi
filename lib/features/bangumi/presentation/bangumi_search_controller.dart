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

  @override
  void onClose() {
    _debounce?.cancel();
    queryController.dispose();
    super.onClose();
  }

  Future<void> search([String? value]) async {
    final keyword = (value ?? queryController.text).trim();
    if (keyword.isEmpty) {
      results.clear();
      message.value = null;
      return;
    }

    loading.value = true;
    message.value = null;
    try {
      final subjects = await _repository.searchAnime(keyword);
      results.assignAll(subjects);
      if (subjects.isEmpty) {
        message.value = '没有找到相关番剧';
      }
    } catch (error) {
      message.value = '搜索失败\n${error.toString()}';
    } finally {
      loading.value = false;
    }
  }
}
