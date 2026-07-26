import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:mutsumi/core/storage/local_storage.dart';
import 'package:mutsumi/features/settings/data/settings_repository.dart';

void main() {
  setUpAll(() async {
    Hive.init('.test_hive/settings_repository');
    await Hive.openBox(LocalStorage.settingsBoxName);
  });

  tearDownAll(() async {
    await Hive.deleteBoxFromDisk(LocalStorage.settingsBoxName);
    await Hive.close();
  });

  test(
    'migrates legacy storage and keeps multiple accounts on one server',
    () async {
      final box = Hive.box(LocalStorage.settingsBoxName);
      await box.clear();
      await box.put('server_url', 'http://localhost:12091/');
      await box.put('server_urls', ['http://localhost:12091/']);
      await box.put('server_credentials', {
        'http://localhost:12091': {'username': 'admin', 'password': 'secret'},
      });
      await box.put('server_tokens', {
        'http://localhost:12091': 'legacy-token',
      });

      await SettingsRepository.migrate();
      final repository = SettingsRepository();
      expect(repository.getCurrentAccount()?.username, 'admin');
      final legacyCredential = await repository.getServerCredential(
        'http://localhost:12091',
      );
      expect(legacyCredential?.username, 'admin');
      expect(legacyCredential?.password, 'secret');
      expect(
        repository.getAccessToken('http://localhost:12091'),
        'legacy-token',
      );

      await repository.saveLogin(
        serverUrl: 'http://localhost:12091/',
        username: 'user',
        password: 'password',
        accessToken: 'user-token',
        permissionGroup: 'admin',
      );
      expect(repository.getAccounts('http://localhost:12091'), hasLength(2));
      expect(repository.getCurrentAccount()?.username, 'user');
      final userCredential = await repository.getServerCredential(
        'http://localhost:12091',
      );
      expect(userCredential?.password, 'password');

      await repository.setCurrentAccount('http://localhost:12091', 'admin');
      expect(repository.getCurrentAccount()?.username, 'admin');
      final currentCredential = await repository.getServerCredential(
        'http://localhost:12091',
      );
      expect(currentCredential?.password, 'secret');
      expect(
        repository.getAccessToken('http://localhost:12091'),
        'legacy-token',
      );
    },
  );

  test('call sites share one repository instance', () {
    expect(identical(SettingsRepository(), SettingsRepository()), isTrue);
  });

  test('setAccessToken only updates the current account', () async {
    final box = Hive.box(LocalStorage.settingsBoxName);
    await box.clear();
    final repository = SettingsRepository();
    await repository.saveLogin(
      serverUrl: 'http://a.test',
      username: 'admin',
      password: 'secret',
      accessToken: 'token-a',
      permissionGroup: 'Admin',
    );
    await repository.saveLogin(
      serverUrl: 'http://b.test',
      username: 'admin',
      password: 'secret',
      accessToken: 'token-b',
      permissionGroup: 'Admin',
    );

    await repository.setAccessToken('http://b.test', 'token-b2');
    expect(repository.getAccessToken('http://b.test'), 'token-b2');

    // http://a.test is not current, so its token must be left untouched.
    await repository.setAccessToken('http://a.test', 'ignored');
    await repository.setCurrentAccount('http://a.test', 'admin');
    expect(repository.getAccessToken('http://a.test'), 'token-a');
  });

  test('trailing slashes in server urls are normalised', () async {
    final box = Hive.box(LocalStorage.settingsBoxName);
    await box.clear();
    final repository = SettingsRepository();
    await repository.saveLogin(
      serverUrl: 'http://c.test/',
      username: 'admin',
      password: 'secret',
      accessToken: 'token-c',
      permissionGroup: 'Admin',
    );

    expect(repository.getAccessToken('http://c.test'), 'token-c');
    expect(repository.getAccessToken('http://c.test/'), 'token-c');
    expect(repository.hasServerUrl('http://c.test//'), isTrue);
  });
}
