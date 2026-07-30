import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/appearance/app_background_preset.dart';
import '../core/widgets/app_glass_background.dart';
import 'app_pages.dart';
import 'app_routes.dart';

class MutsumiApp extends StatelessWidget {
  const MutsumiApp({super.key});

  ThemeData _theme(Brightness brightness, Color seedColor) {
    final baseColorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final colorScheme = brightness == Brightness.dark
        ? baseColorScheme.copyWith(
            surface: _lighten(baseColorScheme.surface, 0.08),
            surfaceDim: _lighten(baseColorScheme.surfaceDim, 0.06),
            surfaceBright: _lighten(baseColorScheme.surfaceBright, 0.1),
            surfaceContainerLowest: _lighten(
              baseColorScheme.surfaceContainerLowest,
              0.05,
            ),
            surfaceContainerLow: _lighten(
              baseColorScheme.surfaceContainerLow,
              0.07,
            ),
            surfaceContainer: _lighten(baseColorScheme.surfaceContainer, 0.09),
            surfaceContainerHigh: _lighten(
              baseColorScheme.surfaceContainerHigh,
              0.11,
            ),
            surfaceContainerHighest: _lighten(
              baseColorScheme.surfaceContainerHighest,
              0.13,
            ),
          )
        : baseColorScheme;
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

  Color _lighten(Color color, double amount) =>
      Color.lerp(color, Colors.white, amount)!;

  @override
  Widget build(BuildContext context) {
    final appearance = Get.find<AppearanceController>();
    return Obx(
      () => GetMaterialApp(
        title: 'Mutsumi',
        theme: _theme(Brightness.light, appearance.themeSeedColor.value),
        darkTheme: _theme(Brightness.dark, appearance.themeSeedColor.value),
        themeMode: switch (appearance.themeMode.value) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        },
        initialRoute: AppRoutes.startup,
        getPages: AppPages.pages,
      ),
    );
  }
}
