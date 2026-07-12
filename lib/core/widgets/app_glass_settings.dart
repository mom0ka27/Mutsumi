import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class AppGlassSettings {
  const AppGlassSettings._();

  static LiquidGlassSettings standard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LiquidGlassSettings.figma(
      refraction: 50,
      depth: 24,
      dispersion: 8,
      frost: 6,
      glassColor: colors.surface.withValues(alpha: 0.2),
    );
  }
}
