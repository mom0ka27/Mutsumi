import 'package:get/get.dart';

import 'anime_service.dart';

class AnimeListStore extends GetxController {
  AnimeListStore({AnimeService? animeService})
    : _animeService = animeService ?? AnimeService();

  final AnimeService _animeService;
  final animes = <AnimeRead>[].obs;
  final series = <SeriesRead>[].obs;
  final isLoading = true.obs;
  final animeMap = <int, AnimeRead>{};

  @override
  void onInit() {
    super.onInit();
    refresh();
  }

  @override
  Future<void> refresh() async {
    isLoading.value = true;
    try {
      final results = await Future.wait([
        _animeService.listAnimes(),
        _animeService.listSeries(),
      ]);
      animes.value = results[0] as List<AnimeRead>;
      series.value = results[1] as List<SeriesRead>;
      _rebuildMap();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> createSeries({
    required String name,
    required List<int> animeIds,
  }) async {
    await _animeService.createSeries(name: name, animeIds: animeIds);
    await refresh();
  }

  List<AnimeRead> get ungroupedAnimes =>
      animes.where((anime) => anime.seriesId == null).toList();

  void _rebuildMap() {
    animeMap.clear();
    for (final anime in animes) {
      animeMap[anime.bangumiId] = anime;
    }
  }
}
