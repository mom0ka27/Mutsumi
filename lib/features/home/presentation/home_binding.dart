import 'package:get/get.dart';

import '../../anime/data/anime_list_store.dart';
import '../../anime/data/anime_service.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../../bangumi/presentation/bangumi_search_controller.dart';
import '../../downloads/data/download_repository.dart';
import '../../downloads/presentation/download_progress_controller.dart';
import '../../auth/presentation/current_user_controller.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_home_controller.dart';
import 'home_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(HomeController.new);
    Get.lazyPut(() => AnimeListStore(animeService: Get.find<AnimeService>()));
    Get.lazyPut(
      () => DownloadProgressController(
        repository: Get.find<DownloadRepository>(),
      ),
    );
    Get.lazyPut(
      () => BangumiSearchController(
        animeListStore: Get.find<AnimeListStore>(),
        repository: Get.find<BangumiRepository>(),
      ),
    );
    Get.lazyPut(
      () => SettingsHomeController(
        settingsRepository: Get.find<SettingsRepository>(),
        currentUserController: Get.find<CurrentUserController>(),
      ),
    );
  }
}
