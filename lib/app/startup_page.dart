import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/widgets/app_glass_background.dart';
import 'startup_controller.dart';

class StartupPage extends GetView<StartupController> {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context) {
    controller;
    final colorScheme = Theme.of(context).colorScheme;

    return GlassScaffold(
      topEdgeFade: true,
      bottomEdgeFade: false,
      enableBackgroundSampling: true,
      background: const AppGlassBackground(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_sync_rounded,
              size: 56,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('正在连接服务器', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
