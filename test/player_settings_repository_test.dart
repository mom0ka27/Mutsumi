import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:mutsumi/core/storage/local_storage.dart';
import 'package:mutsumi/player/model/player_settings.dart';
import 'package:mutsumi/player/model/player_settings_repository.dart';

void main() {
  setUpAll(() async {
    Hive.init('.test_hive/player_settings_repository');
    await Hive.openBox(LocalStorage.settingsBoxName);
  });

  tearDownAll(() async {
    await Hive.deleteBoxFromDisk(LocalStorage.settingsBoxName);
    await Hive.close();
  });

  test('persists normalized player settings', () async {
    final box = Hive.box(LocalStorage.settingsBoxName);
    await box.clear();
    final repository = PlayerSettingsRepository();

    await repository.update(
      const PlayerSettings(
        backgroundPlayback: false,
        availableSpeeds: [2.0, 1.0, 2.0, 3.0],
        longPressSpeed: 3.0,
      ),
    );

    expect(repository.settings.value.backgroundPlayback, isFalse);
    expect(repository.settings.value.availableSpeeds, [1.0, 2.0, 3.0]);
    expect(repository.settings.value.longPressSpeed, 3.0);
  });
}
