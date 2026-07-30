import 'package:get/get.dart';

import '../../settings/data/settings_repository.dart';
import 'connect_server_controller.dart';

class ConnectServerBinding extends Bindings {
  ConnectServerBinding({this.prefillLastServer = true});

  final bool prefillLastServer;

  @override
  void dependencies() {
    Get.lazyPut(
      () => ConnectServerController(
        prefillLastServer: prefillLastServer,
        settingsRepository: Get.isRegistered<SettingsRepository>()
            ? Get.find<SettingsRepository>()
            : SettingsRepository(),
      ),
    );
  }
}
