import 'package:get/get.dart';

import '../features/home/presentation/home_binding.dart';
import '../features/home/presentation/home_page.dart';
import '../features/auth/presentation/auth_session.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/setup/presentation/connect_server_binding.dart';
import '../features/setup/presentation/connect_server_page.dart';
import '../features/settings/presentation/saved_servers_binding.dart';
import '../features/settings/presentation/saved_servers_page.dart';
import 'app_routes.dart';
import 'startup_controller.dart';
import 'startup_page.dart';

abstract final class AppPages {
  static final pages = <GetPage<dynamic>>[
    GetPage(
      name: AppRoutes.startup,
      page: () => const StartupPage(),
      binding: BindingsBuilder(
        () => Get.lazyPut(
          () => StartupController(
            settingsRepository: Get.isRegistered<SettingsRepository>()
                ? Get.find<SettingsRepository>()
                : null,
            authSession: Get.isRegistered<AuthSession>()
                ? Get.find<AuthSession>()
                : null,
          ),
        ),
      ),
    ),
    GetPage(
      name: AppRoutes.savedServers,
      page: () => const SavedServersPage(),
      binding: SavedServersBinding(),
    ),
    GetPage(
      name: AppRoutes.connectServer,
      page: () => const ConnectServerPage(),
      binding: ConnectServerBinding(),
    ),
    GetPage(
      name: AppRoutes.home,
      page: () => const HomePage(),
      binding: HomeBinding(),
    ),
  ];
}
