import 'package:get/get.dart';

import '../../anime/data/anime_list_store.dart';
import '../../anime/data/anime_service.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../data/anime_garden_download_coordinator.dart';
import '../data/anime_garden_repository.dart';
import '../data/local_add_coordinator.dart';
import 'anime_garden_download_controller.dart';
import 'anime_garden_episode_match_controller.dart';
import 'local_add_prepare_controller.dart';

class AnimeGardenDownloadBinding extends Bindings {
  AnimeGardenDownloadBinding({
    required this.subject,
    required this.animeListStore,
  });

  final BangumiSubject subject;
  final AnimeListStore animeListStore;

  @override
  void dependencies() {
    Get.lazyPut(
      () => AnimeGardenDownloadController(
        subject: subject,
        animeListStore: animeListStore,
        repository: Get.find<AnimeGardenRepository>(),
        downloadCoordinator: Get.find<AnimeGardenDownloadCoordinator>(),
      ),
    );
  }
}

class AnimeGardenEpisodeMatchBinding extends Bindings {
  AnimeGardenEpisodeMatchBinding({
    required this.subject,
    this.resource,
    required this.files,
    required this.bangumiEpisodes,
    required this.animeListStore,
    this.onSave,
  });

  final BangumiSubject subject;
  final AnimeGardenResource? resource;
  final List<QBittorrentFile> files;
  final List<BangumiEpisode> bangumiEpisodes;
  final AnimeListStore animeListStore;
  final Future<void> Function(List<AnimeEpisodeCreate> episodes)? onSave;

  @override
  void dependencies() {
    Get.lazyPut(
      () => AnimeGardenEpisodeMatchController(
        subject: subject,
        resource: resource,
        files: files,
        bangumiEpisodes: bangumiEpisodes,
        downloadCoordinator: Get.find<AnimeGardenDownloadCoordinator>(),
        animeListStore: animeListStore,
        onSave: onSave,
      ),
    );
  }
}

class LocalAddPrepareBinding extends Bindings {
  LocalAddPrepareBinding({required this.subject});

  final BangumiSubject subject;

  @override
  void dependencies() {
    Get.lazyPut(
      () => LocalAddPrepareController(
        subject: subject,
        coordinator: Get.find<LocalAddCoordinator>(),
        animeListStore: Get.find<AnimeListStore>(),
      ),
    );
  }
}
