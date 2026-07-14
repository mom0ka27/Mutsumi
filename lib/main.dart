import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app/mutsumi_app.dart';
import 'core/appearance/appearance_settings_repository.dart';
import 'core/logging/app_logger.dart';
import 'core/storage/local_storage.dart';
import 'core/widgets/app_glass_background.dart';
import 'features/auth/presentation/current_user_controller.dart';
import 'features/settings/data/settings_repository.dart';
import 'player/model/dandanplay_repository.dart';
import 'player/player.dart';

late final PackageInfo packageInfo;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  IndexPlayer.init();
  packageInfo = await PackageInfo.fromPlatform();
  await LocalStorage.init();
  await SettingsRepository.migrate();
  await AppearanceSettingsRepository.migrateBackgroundImagePath(
    LocalStorage.applicationSupportPath,
  );
  Get.put(AppearanceController(), permanent: true);
  Get.put(CurrentUserController(), permanent: true);
  Get.put<DandanPlayRepository>(DandanPlayRepository.instance, permanent: true);
  await LiquidGlassWidgets.initialize();
  AppLogger.info(
    'App initialized version=${packageInfo.version}+${packageInfo.buildNumber}',
  );
  runApp(
    LiquidGlassWidgets.wrap(adaptiveQuality: true, child: const MutsumiApp()),
  );
}
