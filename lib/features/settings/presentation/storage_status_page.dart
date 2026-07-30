import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';
import '../../../core/extensions/build_context.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import 'storage_status_controller.dart';

class StorageStatusPage extends GetView<StorageStatusController> {
  const StorageStatusPage({super.key});

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
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
        actions: [
          GlassButton(
            width: 40,
            height: 40,
            iconSize: 20,
            icon: const Icon(Icons.refresh_rounded),
            label: '刷新',
            onTap: () => controller.load(refresh: true),
          ),
        ],
        centerTitle: false,
      ),
      body: Obx(() {
        if (controller.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.forbidden.value) {
          return const _AccessDenied();
        }
        final status = controller.status.value;
        if (status == null) {
          return const SizedBox.shrink();
        }
        return ListView(
          padding: context.pageContentPadding(),
          children: [
            Text('服务器存储', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(status.dataPath, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            _SummaryCard(status: status),
            const SizedBox(height: 20),
            Text('详情', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (status.anime.isEmpty)
              const _EmptyCard()
            else
              GlassCard(
                useOwnLayer: true,
                padding: EdgeInsets.zero,
                shape: LiquidRoundedSuperellipse(
                  borderRadius: Constants.radius.x,
                ),
                settings: AppGlassSettings.standard(context),
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < status.anime.length;
                      index++
                    ) ...[
                      _AnimeStorageTile(anime: status.anime[index]),
                      if (index < status.anime.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.status});

  final StorageStatus status;

  @override
  Widget build(BuildContext context) {
    final diskUsagePercent = status.diskUsedBytes / status.diskTotalBytes * 100;
    return GlassCard(
      useOwnLayer: true,
      padding: const EdgeInsets.all(20),
      shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
      settings: AppGlassSettings.standard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatBytes(status.dataSizeBytes)} · ${status.dataFileCount} 个文件',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '剩余容量',
                  value: formatBytes(status.diskFreeBytes),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '已用容量',
                  value: formatBytes(status.diskUsedBytes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: diskUsagePercent / 100),
          const SizedBox(height: 8),
          Text(
            '磁盘已使用 ${diskUsagePercent.toStringAsFixed(1)}% · 总容量 ${formatBytes(status.diskTotalBytes)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class _AnimeStorageTile extends StatelessWidget {
  const _AnimeStorageTile({required this.anime});

  final AnimeStorage anime;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.folder_rounded),
    title: Text(anime.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      anime.downloadHash ?? '尚未创建下载文件夹',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Text(formatBytes(anime.sizeBytes)),
  );
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) => ListView(
    padding: context.pageContentPadding(),
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
            Text('当前账户没有查看服务器存储信息的权限。', textAlign: TextAlign.center),
          ],
        ),
      ),
    ],
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) => GlassCard(
    useOwnLayer: true,
    padding: const EdgeInsets.all(24),
    shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
    settings: AppGlassSettings.standard(context),
    child: const Center(child: Text('无 Anime')),
  );
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
}
