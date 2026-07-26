import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

import 'package:mutsumi/app/mutsumi_app.dart';
import 'package:mutsumi/core/storage/local_storage.dart';
import 'package:mutsumi/core/widgets/app_glass_background.dart';
import 'package:mutsumi/features/auth/presentation/current_user_controller.dart';
import 'package:mutsumi/features/settings/presentation/saved_servers_page.dart';
import 'package:mutsumi/features/setup/presentation/connect_server_page.dart';

void main() {
  setUpAll(() async {
    Hive.init('.test_hive/widget');
    await Hive.openBox(LocalStorage.settingsBoxName);
    // MutsumiApp resolves these through Get, the same way main() registers them.
    Get.put(AppearanceController(), permanent: true);
    Get.put(CurrentUserController(), permanent: true);
  });

  tearDownAll(() async {
    await Get.deleteAll(force: true);
    await Hive.deleteBoxFromDisk(LocalStorage.settingsBoxName);
    await Hive.close();
  });

  setUp(() async {
    await Hive.box(LocalStorage.settingsBoxName).clear();
  });

  testWidgets('lands on the saved servers page without a saved session', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MutsumiApp());
    await tester.pumpAndSettle();

    expect(find.byType(SavedServersPage), findsOneWidget);
    expect(find.text('已保存服务器'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('offers adding a server from the saved servers page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MutsumiApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_link_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectServerPage), findsOneWidget);
  });
}
