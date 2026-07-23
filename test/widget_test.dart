import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:mutsumi/app/mutsumi_app.dart';
import 'package:mutsumi/core/storage/local_storage.dart';
import 'package:mutsumi/features/settings/data/settings_repository.dart';

void main() {
  setUpAll(() async {
    Hive.init('.test_hive');
    await Hive.openBox(LocalStorage.settingsBoxName);
  });

  tearDownAll(() async {
    await Hive.deleteBoxFromDisk(LocalStorage.settingsBoxName);
    await Hive.close();
  });

  testWidgets('shows connect server page without saved session', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MutsumiApp());
    await tester.pumpAndSettle();

    expect(find.text('连接 Mutsumi Server'), findsOneWidget);
    expect(find.text('连接并检查'), findsOneWidget);
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
}
