import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mutsumi/core/storage/local_storage.dart';
import 'package:mutsumi/features/auth/data/auth_service.dart';
import 'package:mutsumi/features/auth/data/token_refresher.dart';
import 'package:mutsumi/features/settings/data/settings_repository.dart';

const _serverUrl = 'http://localhost:12091';

void main() {
  setUpAll(() async {
    Hive.init('.test_hive/token_refresher');
    await Hive.openBox(LocalStorage.settingsBoxName);
  });

  tearDownAll(() async {
    await Hive.deleteBoxFromDisk(LocalStorage.settingsBoxName);
    await Hive.close();
  });

  setUp(() async {
    await Hive.box(LocalStorage.settingsBoxName).clear();
  });

  Future<void> saveAccount() {
    return SettingsRepository().saveLogin(
      serverUrl: _serverUrl,
      username: 'admin',
      password: 'secret',
      accessToken: 'expired-token',
      permissionGroup: 'Admin',
    );
  }

  test('stores the new token so later requests use it', () async {
    await saveAccount();
    final refresher = TokenRefresher(
      login: (serverUrl, fingerprint, credential) async {
        expect(serverUrl, _serverUrl);
        expect(credential.username, 'admin');
        expect(credential.password, 'secret');
        return const LoginResult(
          accessToken: 'fresh-token',
          permissionGroup: 'Admin',
        );
      },
    );

    expect(await refresher.refresh(_serverUrl), 'fresh-token');
    expect(SettingsRepository().getAccessToken(_serverUrl), 'fresh-token');
  });

  test('concurrent refreshes share a single login', () async {
    await saveAccount();
    var logins = 0;
    final gate = Completer<void>();
    final refresher = TokenRefresher(
      login: (serverUrl, fingerprint, credential) async {
        logins++;
        await gate.future;
        return const LoginResult(
          accessToken: 'fresh-token',
          permissionGroup: 'Admin',
        );
      },
    );

    final futures = [
      refresher.refresh(_serverUrl),
      refresher.refresh(_serverUrl),
      refresher.refresh(_serverUrl),
    ];
    gate.complete();

    expect(await Future.wait(futures), [
      'fresh-token',
      'fresh-token',
      'fresh-token',
    ]);
    expect(logins, 1);
  });

  test('a later refresh logs in again', () async {
    await saveAccount();
    var logins = 0;
    final refresher = TokenRefresher(
      login: (serverUrl, fingerprint, credential) async {
        logins++;
        return LoginResult(
          accessToken: 'token-$logins',
          permissionGroup: 'Admin',
        );
      },
    );

    expect(await refresher.refresh(_serverUrl), 'token-1');
    expect(await refresher.refresh(_serverUrl), 'token-2');
  });

  test('returns null when there are no stored credentials', () async {
    var logins = 0;
    final refresher = TokenRefresher(
      login: (serverUrl, fingerprint, credential) async {
        logins++;
        return null;
      },
    );

    expect(await refresher.refresh(_serverUrl), isNull);
    expect(logins, 0, reason: 'no credentials means no login attempt');
  });

  test('returns null when the server rejects the stored credentials', () async {
    await saveAccount();
    final refresher = TokenRefresher(
      login: (serverUrl, fingerprint, credential) async => null,
    );

    expect(await refresher.refresh(_serverUrl), isNull);
    expect(
      SettingsRepository().getAccessToken(_serverUrl),
      'expired-token',
      reason: 'a failed refresh must not clear the existing token',
    );
  });
}
