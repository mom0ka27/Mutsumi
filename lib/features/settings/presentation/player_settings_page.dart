import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/extensions/build_context.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../player/model/player_settings.dart';
import '../../../player/model/player_settings_repository.dart';

class PlayerSettingsPage extends StatelessWidget {
  const PlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = Get.find<PlayerSettingsRepository>();
    return GlassScaffold(
      topEdgeFade: true,
      bottomEdgeFade: false,
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('播放器', style: Theme.of(context).textTheme.titleLarge),
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
      body: Obx(() {
        final settings = repository.settings.value;
        return ListView(
          padding: context.pageContentPadding(bottom: 20),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('后台播放'),
              subtitle: const Text('离开应用时继续播放当前视频'),
              value: settings.backgroundPlayback,
              onChanged: (enabled) => repository.update(
                settings.copyWith(backgroundPlayback: enabled),
              ),
            ),
            const SizedBox(height: 24),
            Text('可选倍速', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '选择在播放器倍速菜单中显示的选项',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PlayerSettings.supportedSpeeds.map((speed) {
                final selected = settings.availableSpeeds.contains(speed);
                return FilterChip(
                  label: Text(_speedLabel(speed)),
                  selected: selected,
                  onSelected: (value) {
                    if (!value && settings.availableSpeeds.length == 1) return;
                    final speeds = [...settings.availableSpeeds];
                    value ? speeds.add(speed) : speeds.remove(speed);
                    repository.update(
                      settings.copyWith(availableSpeeds: speeds),
                    );
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text('长按倍速', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '在画面上长按或按住键盘右方向键时临时使用',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<double>(
              segments: PlayerSettings.supportedSpeeds
                  .where((speed) => speed >= 1.5)
                  .map(
                    (speed) => ButtonSegment(
                      value: speed,
                      label: Text(_speedLabel(speed)),
                    ),
                  )
                  .toList(),
              selected: {settings.longPressSpeed},
              onSelectionChanged: (values) => repository.update(
                settings.copyWith(longPressSpeed: values.first),
              ),
            ),
          ],
        );
      }),
    );
  }

  String _speedLabel(double speed) =>
      '${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}×';
}
