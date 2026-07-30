import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';
import '../../../core/extensions/build_context.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import 'qbittorrent_settings_controller.dart';

class QBittorrentSettingsView extends GetView<QBittorrentSettingsController> {
  const QBittorrentSettingsView({super.key, this.bottomPadding = 120});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.loading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.forbidden.value) {
        return _AccessDenied(bottomPadding: bottomPadding);
      }
      if (controller.errorMessage.value != null) {
        return const SizedBox.shrink();
      }
      return ListView(
        padding: context.pageContentPadding(bottom: bottomPadding),
        children: [
          Text('下载设置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          GlassCard(
            useOwnLayer: true,
            padding: const EdgeInsets.all(16),
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            settings: AppGlassSettings.standard(context),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            '分享率限制',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          Text(
                            controller.ratioLabel,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      Slider(
                        value: controller.shareRatioSlider.value,
                        min: 0,
                        max: 10,
                        divisions: 100,
                        label: controller.ratioLabel,
                        onChanged: controller.saving.value
                            ? null
                            : controller.setShareRatio,
                      ),
                    ],
                  ),
                  const Text('新任务达到该分享率后，按 qBittorrent 的限额动作处理'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: controller.saving.value ? null : controller.save,
            icon: controller.saving.value
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('保存'),
          ),
        ],
      );
    });
  }
}

class QBittorrentSettingsPage extends GetView<QBittorrentSettingsController> {
  const QBittorrentSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      topEdgeFade: true,
      bottomEdgeFade: false,
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          'qBittorrent',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
        centerTitle: false,
      ),
      body: const QBittorrentSettingsView(bottomPadding: 24),
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) => ListView(
    padding: context.pageContentPadding(bottom: bottomPadding),
    children: [
      GlassCard(
        useOwnLayer: true,
        padding: const EdgeInsets.all(24),
        shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
        settings: AppGlassSettings.standard(context),
        child: const Column(
          children: [
            Icon(Icons.lock_outline_rounded, size: 48),
            SizedBox(height: 16),
            Text(
              '仅管理员可访问',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text('当前账户没有读取或修改 qBittorrent 设置的权限。', textAlign: TextAlign.center),
          ],
        ),
      ),
    ],
  );
}
