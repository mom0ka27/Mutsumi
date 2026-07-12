import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';

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
  late final backgroundImagePath = RxnString(
    _settings.getBackgroundImagePath(),
  );
  late final themeColorSource = _settings.getThemeColorSource().obs;
  late final themeSeedColor = _settings.getThemeSeedColor().obs;

  Future<void> setThemeMode(AppThemeMode value) async {
    themeMode.value = value;
    await _settings.setThemeMode(value);
  }

  Future<bool> selectBackgroundImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) {
      return false;
    }

    final directory = await getApplicationSupportDirectory();
    final backgroundsDirectory = Directory('${directory.path}/backgrounds');
    await backgroundsDirectory.create(recursive: true);
    final extension = image.name.split('.').lastOrNull;
    final target = File(
      '${backgroundsDirectory.path}/background_${DateTime.now().microsecondsSinceEpoch}${extension == null ? '' : '.$extension'}',
    );
    await image.saveTo(target.path);

    final previousPath = backgroundImagePath.value;
    backgroundImagePath.value = target.path;
    await _settings.setBackgroundImagePath(target.path);
    if (themeColorSource.value == AppThemeColorSource.wallpaper) {
      await _updateWallpaperThemeColor(target);
    }
    await _deleteBackgroundImage(previousPath);
    return true;
  }

  Future<void> clearBackgroundImage() async {
    final previousPath = backgroundImagePath.value;
    backgroundImagePath.value = null;
    await _settings.setBackgroundImagePath(null);
    if (themeColorSource.value == AppThemeColorSource.wallpaper) {
      themeColorSource.value = AppThemeColorSource.preset;
      themeSeedColor.value = AppThemeColorPreset.defaultColor;
      await _settings.setThemeColorSource(AppThemeColorSource.preset);
      await _settings.setThemeSeedColor(AppThemeColorPreset.defaultColor);
    }
    await _deleteBackgroundImage(previousPath);
  }

  Future<void> setThemeSeedColor(Color color) async {
    themeColorSource.value = AppThemeColorSource.preset;
    themeSeedColor.value = color;
    await _settings.setThemeColorSource(AppThemeColorSource.preset);
    await _settings.setThemeSeedColor(color);
  }

  Future<bool> useWallpaperThemeColor() async {
    final path = backgroundImagePath.value;
    if (path == null) {
      return false;
    }
    final color = await _extractWallpaperColor(File(path));
    if (color == null) {
      return false;
    }
    themeColorSource.value = AppThemeColorSource.wallpaper;
    themeSeedColor.value = color;
    await _settings.setThemeColorSource(AppThemeColorSource.wallpaper);
    await _settings.setThemeSeedColor(color);
    return true;
  }

  Future<void> disableWallpaperThemeColor() async {
    themeColorSource.value = AppThemeColorSource.preset;
    await _settings.setThemeColorSource(AppThemeColorSource.preset);
  }

  Future<void> _updateWallpaperThemeColor(File file) async {
    final color = await _extractWallpaperColor(file);
    if (color == null) {
      return;
    }
    themeSeedColor.value = color;
    await _settings.setThemeSeedColor(color);
  }

  Future<Color?> _extractWallpaperColor(File file) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        FileImage(file),
        size: const Size(112, 112),
      );
      return palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteBackgroundImage(String? path) async {
    if (path == null) {
      return;
    }
    final directory = await getApplicationSupportDirectory();
    final backgroundsDirectory = Directory('${directory.path}/backgrounds');
    if (!path.startsWith('${backgroundsDirectory.path}/')) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class AppGlassBackground extends StatelessWidget {
  const AppGlassBackground({super.key, this.showCustomImage = true});

  final bool showCustomImage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!showCustomImage) {
      return ColoredBox(color: colors.surface);
    }

    return Obx(() {
      final path = AppearanceController.instance.backgroundImagePath.value;
      if (path == null) {
        return ColoredBox(color: colors.surface);
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: colors.surface),
          RepaintBoundary(
            child: Image.file(
              File(path),
              gaplessPlayback: true,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
          ),
          ColoredBox(color: colors.surface.withValues(alpha: 0.52)),
        ],
      );
    });
  }
}
