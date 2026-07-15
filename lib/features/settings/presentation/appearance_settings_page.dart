import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/appearance/app_background_preset.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/network/app_network_error.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  static const _themeModes = {
    AppThemeMode.system: ('跟随系统', Icons.brightness_auto_rounded),
    AppThemeMode.light: ('浅色模式', Icons.light_mode_rounded),
    AppThemeMode.dark: ('深色模式', Icons.dark_mode_rounded),
  };

  Future<void> _selectBackgroundImage(BuildContext context) async {
    try {
      final selected = await Get.find<AppearanceController>()
          .selectBackgroundImage();
      if (!selected || !context.mounted) return;
    } catch (e) {
      if (context.mounted) {
        await showErrorDialog(
          title: '设置失败',
          message: errorMessageOf(e),
        );
      }
    }
  }

  Future<void> _useWallpaperThemeColor(BuildContext context) async {
    try {
      final updated = await Get.find<AppearanceController>()
          .useWallpaperThemeColor();
      if (!updated && context.mounted) {
        await showErrorDialog(title: '无法取色', message: '请先选择可用的背景图片');
      }
    } catch (e) {
      if (context.mounted) {
        await showErrorDialog(title: '无法取色', message: errorMessageOf(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppearanceController>();
    return GlassScaffold(
      enableBackgroundSampling: true,
      extendBody: true,
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
          padding: const EdgeInsets.fromLTRB(20, Constants.topPadding, 20, 20),
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
            const SizedBox(height: 20),
            Text('主题色', style: Theme.of(context).textTheme.titleMedium),
            Obx(() {
              final wallpaperColorEnabled =
                  controller.themeColorSource.value ==
                  AppThemeColorSource.wallpaper;
              return Opacity(
                opacity: wallpaperColorEnabled ? 0.45 : 1,
                child: IgnorePointer(
                  ignoring: wallpaperColorEnabled,
                  child: GridView.count(
                    padding: const EdgeInsets.all(4),
                    crossAxisCount: 5,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1,
                    children: AppThemeColorPreset.values
                        .map(
                          (preset) => _ThemeColorOption(
                            color: preset.color,
                            selected:
                                controller.themeSeedColor.value.toARGB32() ==
                                preset.color.toARGB32(),
                            onTap: () =>
                                controller.setThemeSeedColor(preset.color),
                          ),
                        )
                        .toList(),
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
            Text('背景', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Obx(() {
              final hasBackgroundImage =
                  controller.backgroundImagePath.value != null;
              return Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      hasBackgroundImage
                          ? Icons.image_rounded
                          : Icons.wallpaper_rounded,
                    ),
                    title: Text(hasBackgroundImage ? '已设置背景图片' : '默认背景'),
                    subtitle: Text(
                      hasBackgroundImage ? '图片将覆盖所有页面背景' : '使用主题默认背景',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _selectBackgroundImage(context),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用背景取色'),
                    subtitle: const Text('根据背景图片自动调整主题色'),
                    value:
                        controller.themeColorSource.value ==
                        AppThemeColorSource.wallpaper,
                    onChanged: hasBackgroundImage
                        ? (enabled) async {
                            if (enabled) {
                              await _useWallpaperThemeColor(context);
                            } else {
                              await controller.disableWallpaperThemeColor();
                            }
                          }
                        : null,
                  ),
                  if (hasBackgroundImage) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.opacity_rounded),
                        const SizedBox(width: 16),
                        const Text('背景遮罩'),
                        const Spacer(),
                        Text(
                          '${(controller.backgroundOverlayOpacity.value * 100).round()}%',
                        ),
                      ],
                    ),
                    Slider(
                      value: controller.backgroundOverlayOpacity.value,
                      min: 0,
                      max: 0.8,
                      divisions: 16,
                      label:
                          '${(controller.backgroundOverlayOpacity.value * 100).round()}%',
                      onChanged: controller.setBackgroundOverlayOpacity,
                    ),
                  ],
                  if (hasBackgroundImage)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: controller.clearBackgroundImage,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('恢复默认背景'),
                      ),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ThemeColorOption extends StatelessWidget {
  const _ThemeColorOption({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? colors.onSurface : Colors.transparent,
              width: selected ? 3 : 0,
            ),
          ),
          child: const SizedBox.square(dimension: 42),
        ),
      ),
    );
  }
}
