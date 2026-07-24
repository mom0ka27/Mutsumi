import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mutsumi/core/appearance/app_image_cache.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';
import '../logging/app_logger.dart';

import '../appearance/app_background_preset.dart';
import '../appearance/appearance_settings_repository.dart';
import '../storage/local_storage.dart';

class AppearanceController extends GetxService {
  final _settings = AppearanceSettingsRepository();
  late final themeMode = _settings.getThemeMode().obs;
  late final backgroundImagePath = RxnString(
    _resolveBackgroundImagePath(_settings.getBackgroundImagePath()),
  );
  late final themeColorSource = _settings.getThemeColorSource().obs;
  late final themeSeedColor = _settings.getThemeSeedColor().obs;
  late final backgroundOverlayOpacity = _settings
      .getBackgroundOverlayOpacity()
      .obs;

  Future<void> setThemeMode(AppThemeMode value) async {
    themeMode.value = value;
    await _settings.setThemeMode(value);
  }

  Future<void> setBackgroundOverlayOpacity(double value) async {
    final opacity = value.clamp(0, 0.8).toDouble();
    backgroundOverlayOpacity.value = opacity;
    await _settings.setBackgroundOverlayOpacity(opacity);
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
    if (!await target.exists() || await target.length() == 0) {
      if (await target.exists()) {
        await target.delete();
      }
      throw StateError('背景图片保存失败');
    }

    final previousPath = backgroundImagePath.value;
    backgroundImagePath.value = target.path;
    await _settings.setBackgroundImagePath(
      'backgrounds/${target.uri.pathSegments.last}',
    );
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
    } catch (error, stackTrace) {
      AppLogger.error(
        '背景图片取色失败',
        tag: 'Appearance',
        error: error,
        stackTrace: stackTrace,
      );
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

  String? _resolveBackgroundImagePath(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    if (path.startsWith('/')) {
      return path;
    }
    return '${LocalStorage.applicationSupportPath}/$path';
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

    final size = MediaQuery.of(context).size;

    return Obx(() {
      final path = Get.find<AppearanceController>().backgroundImagePath.value;
      final overlayOpacity =
          Get.find<AppearanceController>().backgroundOverlayOpacity.value;
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
              cacheWidth: AppImageCache.dimension(context, size.width),
              cacheHeight: AppImageCache.dimension(context, size.height),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
          ),
          ColoredBox(color: colors.surface.withValues(alpha: overlayOpacity)),
        ],
      );
    });
  }
}
