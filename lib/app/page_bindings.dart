import 'package:get/get.dart';

import '../features/anime/data/anime_service.dart';
import '../features/anime/presentation/anime_detail_controller.dart';
import '../features/anime/presentation/anime_play_controller.dart';
import '../features/anime_garden/data/anime_garden_download_coordinator.dart';
import '../features/auth/presentation/auth_session.dart';
import '../features/auth/presentation/login_controller.dart';
import '../features/bangumi/data/bangumi_repository.dart';
import '../features/bangumi/presentation/bangumi_detail_controller.dart';
import '../features/settings/presentation/qbittorrent_settings_controller.dart';
import '../features/settings/presentation/server_update_controller.dart';
import '../features/settings/presentation/storage_status_controller.dart';
import '../features/settings/data/authenticated_server_client.dart';
import '../features/settings/data/server_update_service.dart';
import '../features/setup/presentation/create_admin_controller.dart';
import '../features/users/data/users_repository.dart';
import '../features/users/presentation/users_management_controller.dart';

class LoginBinding extends Bindings {
  LoginBinding({
    required this.serverUrl,
    this.certificateSha256,
    this.serverName,
  });

  final String serverUrl;
  final String? certificateSha256;
  final String? serverName;

  @override
  void dependencies() {
    Get.lazyPut(
      () => LoginController(
        serverUrl: serverUrl,
        certificateSha256: certificateSha256,
        serverName: serverName,
        authSession: Get.find<AuthSession>(),
      ),
    );
  }
}

class CreateAdminBinding extends Bindings {
  CreateAdminBinding({
    required this.serverUrl,
    this.certificateSha256,
    this.initialServerName = '',
  });

  final String serverUrl;
  final String? certificateSha256;
  final String initialServerName;

  @override
  void dependencies() {
    Get.lazyPut(
      () => CreateAdminController(
        serverUrl: serverUrl,
        certificateSha256: certificateSha256,
        initialServerName: initialServerName,
        authSession: Get.find<AuthSession>(),
      ),
    );
  }
}

class AnimeDetailBinding extends Bindings {
  AnimeDetailBinding({required this.animeId, this.initialAnime});

  final int animeId;
  final AnimeRead? initialAnime;

  @override
  void dependencies() {
    Get.lazyPut(
      () => AnimeDetailController(
        animeId: animeId,
        initialAnime: initialAnime,
        animeService: Get.find<AnimeService>(),
        bangumiRepository: Get.find<BangumiRepository>(),
        downloadCoordinator: Get.find<AnimeGardenDownloadCoordinator>(),
      ),
    );
  }
}

class AnimePlayBinding extends Bindings {
  AnimePlayBinding({
    required this.anime,
    required this.episodes,
    required this.initialEpisode,
  });

  final AnimeRead anime;
  final List<AnimeEpisodeRead> episodes;
  final int initialEpisode;

  @override
  void dependencies() {
    Get.lazyPut(
      () => AnimePlayController(
        anime: anime,
        episodes: episodes,
        initialEpisode: initialEpisode,
        animeService: Get.find<AnimeService>(),
      ),
    );
  }
}

class BangumiDetailBinding extends Bindings {
  BangumiDetailBinding({required this.subject});

  final BangumiSubject subject;

  @override
  void dependencies() {
    Get.lazyPut(
      () => BangumiDetailController(
        subject: subject,
        repository: Get.find<BangumiRepository>(),
      ),
    );
  }
}

class UsersManagementBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => UsersManagementController(repository: Get.find<UsersRepository>()),
    );
  }
}

class StorageStatusBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => StorageStatusController(
        client: Get.find<AuthenticatedServerClient>(),
      ),
    );
  }
}

class QBittorrentSettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => QBittorrentSettingsController(
        client: Get.find<AuthenticatedServerClient>(),
      ),
    );
  }
}

class ServerUpdateBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ServerUpdateController(service: Get.find<ServerUpdateService>()),
    );
  }
}
