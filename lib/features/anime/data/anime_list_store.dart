import 'package:get/get.dart';

import 'anime_service.dart';

class AnimeListStore extends GetxController {
  AnimeListStore({AnimeService? animeService})
    : _animeService = animeService ?? AnimeService();

  final AnimeService _animeService;
  final animes = <AnimeRead>[].obs;
  final isLoading = true.obs;
  final animeMap = <int, AnimeRead>{};

  @override
  void onInit() {
    super.onInit();
    refresh();
  }

  Future<void> refresh() async {
    isLoading.value = true;
    try {
      animes.value = await _animeService.listAnimes();
      _rebuildMap();
    } finally {
      isLoading.value = false;
    }
  }

  void _rebuildMap() {
    animeMap.clear();
    for (final anime in animes) {
      animeMap[anime.bangumiId] = anime;
    }
  }
}
