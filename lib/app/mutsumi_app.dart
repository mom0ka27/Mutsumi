import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../features/home/presentation/home_page.dart';
import '../features/setup/presentation/connect_server_page.dart';
import '../core/appearance/app_background_preset.dart';
import '../core/widgets/app_glass_background.dart';
import 'startup_page.dart';

class MutsumiApp extends StatelessWidget {
  const MutsumiApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: brightness,
    );
    final outline = colorScheme.outlineVariant.withValues(alpha: 0.56);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface.withValues(alpha: 0.56),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: DividerThemeData(color: outline),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => GetMaterialApp(
        title: 'Mutsumi',
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
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
