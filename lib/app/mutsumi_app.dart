import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../features/home/presentation/home_page.dart';
import '../features/setup/presentation/connect_server_page.dart';
import '../core/appearance/app_background_preset.dart';
import '../core/widgets/app_glass_background.dart';
import 'startup_page.dart';

class MutsumiApp extends StatelessWidget {
  const MutsumiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => GetMaterialApp(
        title: 'Mutsumi',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: switch (AppearanceController.instance.themeMode.value) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        },
        initialRoute: StartupPage.routeName,
        getPages: [
          GetPage(name: StartupPage.routeName, page: () => const StartupPage()),
          GetPage(
            name: ConnectServerPage.routeName,
            page: () => const ConnectServerPage(),
          ),
          GetPage(name: HomePage.routeName, page: () => const HomePage()),
        ],
      ),
    );
  }
}
