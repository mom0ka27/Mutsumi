import 'package:get/get.dart';

import '../core/widgets/app_glass_background.dart';
import '../features/anime/data/anime_service.dart';
import '../features/anime_garden/data/anime_garden_download_coordinator.dart';
import '../features/anime_garden/data/anime_garden_repository.dart';
import '../features/anime_garden/data/local_add_coordinator.dart';
import '../features/auth/data/token_refresher.dart';
import '../features/auth/presentation/auth_session.dart';
import '../features/auth/presentation/current_user_controller.dart';
import '../features/bangumi/data/bangumi_repository.dart';
import '../features/downloads/data/download_repository.dart';
import '../features/settings/data/authenticated_server_client.dart';
import '../features/settings/data/server_update_service.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/users/data/users_repository.dart';
import '../player/model/dandanplay_repository.dart';
import '../player/model/player_settings_repository.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    final settingsRepository = Get.put(SettingsRepository(), permanent: true);
    Get.put(AppearanceController(), permanent: true);
    final currentUserController = Get.put(
      CurrentUserController(),
      permanent: true,
    );
    Get.put(
      AuthSession(
        settingsRepository: settingsRepository,
        currentUserController: currentUserController,
      ),
      permanent: true,
    );
    final tokenRefresher = Get.put(
      TokenRefresher(
        settingsRepository: settingsRepository,
        currentUserController: currentUserController,
      ),
      permanent: true,
    );
    final serverClient = Get.put(
      AuthenticatedServerClient(
        settingsRepository: settingsRepository,
        tokenRefresher: tokenRefresher,
      ),
      permanent: true,
    );
    final animeService = Get.put(
      AnimeService(
        settingsRepository: settingsRepository,
        serverClient: serverClient,
      ),
      permanent: true,
    );
    final bangumiRepository = Get.put(BangumiRepository(), permanent: true);
    Get.put(AnimeGardenRepository(), permanent: true);
    Get.put(DownloadRepository(client: serverClient), permanent: true);
    Get.put(UsersRepository(client: serverClient), permanent: true);
    Get.put(ServerUpdateService(client: serverClient), permanent: true);
    Get.put(
      AnimeGardenDownloadCoordinator(
        animeService: animeService,
        bangumiRepository: bangumiRepository,
      ),
      permanent: true,
    );
    Get.put(
      LocalAddCoordinator(
        animeService: animeService,
        bangumiRepository: bangumiRepository,
      ),
      permanent: true,
    );
    Get.put<DandanPlayRepository>(
      DandanPlayRepository.instance,
      permanent: true,
    );
    Get.put(PlayerSettingsRepository(), permanent: true);
  }
}
