import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../appearance/app_background_preset.dart';
import '../../features/settings/data/settings_repository.dart';

class AppearanceController extends GetxService {
  static AppearanceController get instance {
    if (Get.isRegistered<AppearanceController>()) {
      return Get.find<AppearanceController>();
    }
    return Get.put(AppearanceController(), permanent: true);
  }

  final _settings = SettingsRepository();
  late final themeMode = _settings.getThemeMode().obs;

  Future<void> setThemeMode(AppThemeMode value) async {
    themeMode.value = value;
    await _settings.setThemeMode(value);
  }
}

class AppGlassBackground extends StatelessWidget {
  const AppGlassBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(color: colors.surface);
  }
}
