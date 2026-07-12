import 'package:flutter/material.dart';

enum AppThemeMode { system, light, dark }

enum AppThemeColorSource { preset, wallpaper }

class AppThemeColorPreset {
  const AppThemeColorPreset({
    required this.name,
    required this.color,
    required this.icon,
  });

  final String name;
  final Color color;
  final IconData icon;

  static const defaultColor = Color(0xFF779977);

  static const values = [
    AppThemeColorPreset(
      name: '默认绿',
      color: defaultColor,
      icon: Icons.eco_rounded,
    ),
    AppThemeColorPreset(
      name: '海洋蓝',
      color: Color(0xFF3D7EFF),
      icon: Icons.water_rounded,
    ),
    AppThemeColorPreset(
      name: '紫罗兰',
      color: Color(0xFF8B5CF6),
      icon: Icons.auto_awesome_rounded,
    ),
    AppThemeColorPreset(
      name: '樱花粉',
      color: Color(0xFFEC6C9B),
      icon: Icons.favorite_rounded,
    ),
    AppThemeColorPreset(
      name: '琥珀橙',
      color: Color(0xFFF59E0B),
      icon: Icons.wb_sunny_rounded,
    ),
    AppThemeColorPreset(
      name: '薄荷青',
      color: Color(0xFF14B8A6),
      icon: Icons.spa_rounded,
    ),
    AppThemeColorPreset(
      name: '珊瑚红',
      color: Color(0xFFEF4444),
      icon: Icons.local_fire_department_rounded,
    ),
    AppThemeColorPreset(
      name: '靛蓝',
      color: Color(0xFF4F46E5),
      icon: Icons.nightlight_round,
    ),
    AppThemeColorPreset(
      name: '玫瑰紫',
      color: Color(0xFFC026D3),
      icon: Icons.local_florist_rounded,
    ),
    AppThemeColorPreset(
      name: '青柠绿',
      color: Color(0xFF65A30D),
      icon: Icons.grass_rounded,
    ),
  ];
}
