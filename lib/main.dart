import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app/mutsumi_app.dart';
import 'core/logging/app_logger.dart';
import 'core/storage/local_storage.dart';
import 'core/widgets/app_glass_background.dart';
import 'player/player.dart';

late final PackageInfo packageInfo;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  IndexPlayer.init();
  packageInfo = await PackageInfo.fromPlatform();
  await LocalStorage.init();
  AppearanceController.instance;
  await LiquidGlassWidgets.initialize();
  AppLogger.info(
    'App initialized version=${packageInfo.version}+${packageInfo.buildNumber}',
  );
  runApp(
    LiquidGlassWidgets.wrap(adaptiveQuality: true, child: const MutsumiApp()),
  );
}
