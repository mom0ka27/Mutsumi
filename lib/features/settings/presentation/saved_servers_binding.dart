import 'package:get/get.dart';

import '../data/settings_repository.dart';
import 'saved_servers_controller.dart';

class SavedServersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => SavedServersController(
        settingsRepository: Get.find<SettingsRepository>(),
      ),
    );
  }
}
