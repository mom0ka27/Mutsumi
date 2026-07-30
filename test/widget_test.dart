import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

import 'package:mutsumi/app/app_pages.dart';
import 'package:mutsumi/app/app_routes.dart';
import 'package:mutsumi/core/storage/local_storage.dart';
import 'package:mutsumi/core/widgets/app_glass_background.dart';
import 'package:mutsumi/features/auth/presentation/current_user_controller.dart';
import 'package:mutsumi/features/settings/data/settings_repository.dart';
import 'package:mutsumi/features/settings/presentation/saved_servers_page.dart';
import 'package:mutsumi/features/setup/presentation/connect_server_binding.dart';
import 'package:mutsumi/features/setup/presentation/connect_server_page.dart';

void main() {
  setUpAll(() async {
    Hive.init('.test_hive/widget');
    await Hive.openBox(LocalStorage.settingsBoxName);
  });

  tearDownAll(() async {
    await Get.deleteAll(force: true);
    await Hive.deleteBoxFromDisk(LocalStorage.settingsBoxName);
    await Hive.close();
  });

  setUp(() async {
    Get.reset();
    Get.put(AppearanceController(), permanent: true);
    Get.put(CurrentUserController(), permanent: true);
    Get.put(SettingsRepository(), permanent: true);
    await Hive.box(LocalStorage.settingsBoxName).clear();
  });

  testWidgets('lands on the saved servers page without a saved session', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(initialRoute: AppRoutes.startup, getPages: AppPages.pages),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(SavedServersPage), findsOneWidget);
    expect(find.text('已保存服务器'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('renders the add-server page with its binding', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        initialBinding: ConnectServerBinding(prefillLastServer: false),
        home: const ConnectServerPage(
          prefillLastServer: false,
          showBackButton: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ConnectServerPage), findsOneWidget);
  });
}
