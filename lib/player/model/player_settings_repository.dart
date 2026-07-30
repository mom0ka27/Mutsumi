import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

import '../../core/storage/local_storage.dart';
import 'player_settings.dart';

class PlayerSettingsRepository {
  factory PlayerSettingsRepository() => _shared;

  PlayerSettingsRepository._();

  static final PlayerSettingsRepository _shared = PlayerSettingsRepository._();
  static const _storageKey = 'player_settings_v1';

  Box get _box => Hive.box(LocalStorage.settingsBoxName);

  late final settings = _read().obs;

  Future<void> update(PlayerSettings value) async {
    final normalized = _normalize(value);
    await _box.put(_storageKey, {
      'background_playback': normalized.backgroundPlayback,
      'available_speeds': normalized.availableSpeeds,
      'long_press_speed': normalized.longPressSpeed,
    });
    settings.value = normalized;
  }

  PlayerSettings _read() {
    final value = _box.get(_storageKey);
    if (value is! Map) return const PlayerSettings();
    final speeds = value['available_speeds'] is List
        ? (value['available_speeds'] as List)
              .whereType<num>()
              .map((speed) => speed.toDouble())
              .toList()
        : PlayerSettings.defaultAvailableSpeeds;
    return _normalize(
      PlayerSettings(
        backgroundPlayback: value['background_playback'] is bool
            ? value['background_playback'] as bool
            : true,
        availableSpeeds: speeds,
        longPressSpeed: value['long_press_speed'] is num
            ? (value['long_press_speed'] as num).toDouble()
            : 2.0,
      ),
    );
  }

  PlayerSettings _normalize(PlayerSettings value) {
    final speeds =
        value.availableSpeeds
            .where(PlayerSettings.supportedSpeeds.contains)
            .toSet()
            .toList()
          ..sort();
    if (speeds.isEmpty) speeds.add(1.0);
    final longPressSpeed =
        PlayerSettings.supportedSpeeds.contains(value.longPressSpeed)
        ? value.longPressSpeed
        : 2.0;
    return PlayerSettings(
      backgroundPlayback: value.backgroundPlayback,
      availableSpeeds: List.unmodifiable(speeds),
      longPressSpeed: longPressSpeed,
    );
  }
}
