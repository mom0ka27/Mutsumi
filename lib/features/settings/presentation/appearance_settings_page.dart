import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/appearance/app_background_preset.dart';
import '../../../core/widgets/app_glass_background.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  static const _themeModes = {
    AppThemeMode.system: ('跟随系统', Icons.brightness_auto_rounded),
    AppThemeMode.light: ('浅色模式', Icons.light_mode_rounded),
    AppThemeMode.dark: ('深色模式', Icons.dark_mode_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final controller = AppearanceController.instance;
    return GlassScaffold(
      enableBackgroundSampling: false,
      extendBody: false,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('外观', style: Theme.of(context).textTheme.titleLarge),
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
        centerTitle: false,
      ),
      body: Obx(
        () => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<AppThemeMode>(
              segments: _themeModes.entries
                  .map(
                    (entry) => ButtonSegment(
                      value: entry.key,
                      icon: Icon(entry.value.$2),
                      label: Text(entry.value.$1),
                    ),
                  )
                  .toList(),
              selected: {controller.themeMode.value},
              onSelectionChanged: (values) {
                controller.setThemeMode(values.first);
              },
            ),
          ],
        ),
      ),
    );
  }
}
