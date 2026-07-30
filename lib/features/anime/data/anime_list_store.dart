import 'dart:async';

import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import 'anime_service.dart';

class AnimeListStore extends GetxController {
  AnimeListStore({
    AnimeService? animeService,
    Future<void> Function({
      required String title,
      required String message,
      Object? error,
    })?
    errorDialog,
    void Function(String title, String message)? notification,
  }) : _animeService = animeService ?? AnimeService(),
       _errorDialog = errorDialog ?? showErrorDialog,
       _notification = notification ?? Get.snackbar;

  final AnimeService _animeService;
  final Future<void> Function({
    required String title,
    required String message,
    Object? error,
  })
  _errorDialog;
  final void Function(String title, String message) _notification;
  final animes = <AnimeRead>[].obs;
  final series = <SeriesRead>[].obs;
  final isLoading = true.obs;
  final animeMap = <int, AnimeRead>{};
  Future<void>? _refreshing;
  var _showingError = false;

  @override
  void onInit() {
    super.onInit();
    unawaited(refresh());
  }

  @override
  Future<void> refresh() async {
    try {
      await _refreshData();
    } catch (error) {
      unawaited(_showError(title: '加载 Anime 失败', error: error));
    }
  }

  Future<void> createSeries({
    required String name,
    required List<int> animeIds,
  }) async {
    try {
      await _animeService.createSeries(name: name, animeIds: animeIds);
      await _refreshData();
      if (!isClosed) {
        _notification('Series 已新建', name);
      }
    } catch (error) {
      unawaited(_showError(title: '新建 Series 失败', error: error));
    }
  }

  List<AnimeRead> get ungroupedAnimes =>
      animes.where((anime) => anime.seriesId == null).toList();

  Future<void> _refreshData() {
    final refreshing = _refreshing;
    if (refreshing != null) return refreshing;

    final operation = _load();
    _refreshing = operation;
    return operation.whenComplete(() {
      if (identical(_refreshing, operation)) {
        _refreshing = null;
      }
    });
  }

  Future<void> _load() async {
    isLoading.value = true;
    try {
      final results = await Future.wait([
        _animeService.listAnimes(),
        _animeService.listSeries(),
      ]);
      if (isClosed) return;
      animes.value = results[0] as List<AnimeRead>;
      series.value = results[1] as List<SeriesRead>;
      _rebuildMap();
    } finally {
      if (!isClosed) isLoading.value = false;
    }
  }

  Future<void> _showError({
    required String title,
    required Object error,
  }) async {
    if (_showingError || isClosed) return;
    _showingError = true;
    try {
      await _errorDialog(
        title: title,
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      _showingError = false;
    }
  }

  void _rebuildMap() {
    animeMap.clear();
    for (final anime in animes) {
      animeMap[anime.bangumiId] = anime;
    }
  }
}
