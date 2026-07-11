import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:mutsumi/app/mutsumi_app.dart';
import 'package:mutsumi/core/storage/local_storage.dart';

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
}
