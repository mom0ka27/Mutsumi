import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

import 'package:mutsumi/core/extensions/build_context.dart';
import 'package:mutsumi/core/storage/local_storage.dart';
import 'package:mutsumi/core/widgets/app_glass_background.dart';
import 'package:mutsumi/app/page_bindings.dart';
import 'package:mutsumi/features/auth/presentation/auth_session.dart';
import 'package:mutsumi/features/auth/presentation/current_user_controller.dart';
import 'package:mutsumi/features/auth/presentation/login_page.dart';
import 'package:mutsumi/features/settings/data/settings_repository.dart';
import 'package:mutsumi/features/settings/presentation/saved_servers_binding.dart';
import 'package:mutsumi/features/settings/presentation/saved_servers_page.dart';
import 'package:mutsumi/features/setup/presentation/connect_server_page.dart';
import 'package:mutsumi/features/setup/presentation/connect_server_binding.dart';
import 'package:mutsumi/features/setup/presentation/create_admin_page.dart';

/// 一台带刘海的手机横屏时的视口：可用高度只有 390，且左右各有安全区。
/// 这正是原先那些按竖屏调好的固定留白会把内容挤到溢出的场景。
const _landscapeSize = Size(844, 390);
const _landscapeDevicePixelRatio = 2.0;
const _landscapeViewPadding = FakeViewPadding(
  left: 118,
  right: 118,
  bottom: 42,
);

void main() {
  setUpAll(() async {
    Hive.init('.test_hive/landscape');
    await Hive.openBox(LocalStorage.settingsBoxName);
    Get.put(AppearanceController(), permanent: true);
    Get.put(CurrentUserController(), permanent: true);
    Get.put(SettingsRepository(), permanent: true);
    Get.put(AuthSession(), permanent: true);
  });

  tearDownAll(() async {
    await Get.deleteAll(force: true);
    await Hive.deleteBoxFromDisk(LocalStorage.settingsBoxName);
    await Hive.close();
  });

  setUp(() async {
    await Hive.box(LocalStorage.settingsBoxName).clear();
  });

  Future<void> pumpLandscape(
    WidgetTester tester,
    Widget page, {
    Bindings? binding,
  }) async {
    tester.view.devicePixelRatio = _landscapeDevicePixelRatio;
    tester.view.physicalSize = _landscapeSize * _landscapeDevicePixelRatio;
    tester.view.padding = _landscapeViewPadding;
    tester.view.viewPadding = _landscapeViewPadding;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      GetMaterialApp(initialBinding: binding, home: page),
    );
    await tester.pumpAndSettle();
  }

  /// 布局溢出会以 FlutterError 的形式在绘制阶段抛出，这里把它捞出来断言。
  void expectNoLayoutOverflow(WidgetTester tester) {
    expect(tester.takeException(), isNull);
  }

  testWidgets('已保存服务器页横屏不溢出', (tester) async {
    await pumpLandscape(
      tester,
      const SavedServersPage(),
      binding: SavedServersBinding(),
    );

    expect(find.byType(SavedServersPage), findsOneWidget);
    expectNoLayoutOverflow(tester);
  });

  testWidgets('连接服务器页横屏不溢出', (tester) async {
    await pumpLandscape(
      tester,
      const ConnectServerPage(),
      binding: ConnectServerBinding(),
    );

    expect(find.byType(ConnectServerPage), findsOneWidget);
    expectNoLayoutOverflow(tester);
  });

  testWidgets('登录页横屏不溢出并可滚动', (tester) async {
    await pumpLandscape(
      tester,
      const LoginPage(),
      binding: LoginBinding(serverUrl: 'http://127.0.0.1:12091'),
    );

    expect(find.byType(LoginPage), findsOneWidget);
    // 横屏放不下整张表单，必须靠滚动而不是硬挤。
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expectNoLayoutOverflow(tester);
  });

  testWidgets('创建管理员页横屏不溢出', (tester) async {
    await pumpLandscape(
      tester,
      const CreateAdminPage(),
      binding: CreateAdminBinding(serverUrl: 'http://127.0.0.1:12091'),
    );

    expect(find.byType(CreateAdminPage), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expectNoLayoutOverflow(tester);
  });

  testWidgets('横屏内容留白让开左右安全区，且比竖屏更紧凑', (tester) async {
    late EdgeInsets landscapePadding;
    late EdgeInsets portraitPadding;

    Widget probe(void Function(EdgeInsets) capture) => Builder(
      builder: (context) {
        capture(context.pageContentPadding());
        return const SizedBox.shrink();
      },
    );

    await pumpLandscape(tester, probe((value) => landscapePadding = value));

    tester.view.devicePixelRatio = _landscapeDevicePixelRatio;
    tester.view.physicalSize =
        const Size(390, 844) * _landscapeDevicePixelRatio;
    const portraitViewPadding = FakeViewPadding(top: 118, bottom: 68);
    tester.view.padding = portraitViewPadding;
    tester.view.viewPadding = portraitViewPadding;
    await tester.pumpWidget(
      GetMaterialApp(home: probe((value) => portraitPadding = value)),
    );
    await tester.pumpAndSettle();

    expect(landscapePadding.left, greaterThan(portraitPadding.left));
    expect(landscapePadding.right, greaterThan(portraitPadding.right));
    expect(landscapePadding.top, lessThan(portraitPadding.top));
  });
}
