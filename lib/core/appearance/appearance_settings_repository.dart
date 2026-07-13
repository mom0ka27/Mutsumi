import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

import 'app_background_preset.dart';
import '../storage/local_storage.dart';

class AppearanceSettingsRepository {
  AppearanceSettingsRepository()
    : _box = Hive.box(LocalStorage.settingsBoxName);

  static const _themeModeKey = 'appearance_theme_mode_v1';
  static const _backgroundImagePathKey = 'appearance_background_image_path_v1';
  static const _backgroundOverlayOpacityKey =
      'appearance_background_overlay_opacity_v1';
  static const _themeColorSourceKey = 'appearance_theme_color_source_v1';
  static const _themeSeedColorKey = 'appearance_theme_seed_color_v1';

  final Box _box;

  AppThemeMode getThemeMode() {
    final value = _box.get(_themeModeKey) as String?;
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AppThemeMode.system,
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) =>
      _box.put(_themeModeKey, mode.name);

  AppThemeColorSource getThemeColorSource() {
    final value = _box.get(_themeColorSourceKey) as String?;
    return AppThemeColorSource.values.firstWhere(
      (source) => source.name == value,
      orElse: () => AppThemeColorSource.preset,
    );
  }

  Future<void> setThemeColorSource(AppThemeColorSource value) =>
      _box.put(_themeColorSourceKey, value.name);

  Color getThemeSeedColor() {
    final value = _box.get(_themeSeedColorKey) as int?;
    return Color(value ?? AppThemeColorPreset.defaultColor.toARGB32());
  }

  Future<void> setThemeSeedColor(Color value) =>
      _box.put(_themeSeedColorKey, value.toARGB32());

  String? getBackgroundImagePath() =>
      _box.get(_backgroundImagePathKey) as String?;

  Future<void> setBackgroundImagePath(String? value) => value == null
      ? _box.delete(_backgroundImagePathKey)
      : _box.put(_backgroundImagePathKey, value);

  double getBackgroundOverlayOpacity() {
    final value = _box.get(_backgroundOverlayOpacityKey) as num?;
    return (value?.toDouble() ?? 0.36).clamp(0, 0.8);
  }

  Future<void> setBackgroundOverlayOpacity(double value) =>
      _box.put(_backgroundOverlayOpacityKey, value.clamp(0, 0.8));

  static Future<void> migrateBackgroundImagePath(
    String applicationSupportPath,
  ) async {
    final repository = AppearanceSettingsRepository();
    final value = repository.getBackgroundImagePath();
    if (value == null || !value.startsWith('/')) {
      return;
    }
    final backgroundsPath = '$applicationSupportPath/backgrounds/';
    if (!value.startsWith(backgroundsPath) || !await File(value).exists()) {
      await repository.setBackgroundImagePath(null);
      return;
    }
    await repository.setBackgroundImagePath(
      'backgrounds/${File(value).uri.pathSegments.last}',
    );
  }
}
