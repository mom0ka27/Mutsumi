import 'package:get/get.dart';

import '../../auth/presentation/current_user_controller.dart';
import '../data/settings_repository.dart';
import 'settings_home_controller.dart';

class SettingsHomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => SettingsHomeController(
        settingsRepository: Get.find<SettingsRepository>(),
        currentUserController: Get.find<CurrentUserController>(),
      ),
    );
  }
}
