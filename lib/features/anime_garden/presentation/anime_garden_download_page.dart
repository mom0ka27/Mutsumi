import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../data/anime_garden_repository.dart';
import 'anime_garden_download_controller.dart';

class AnimeGardenDownloadPage extends StatelessWidget {
  const AnimeGardenDownloadPage({
    super.key,
    required this.subject,
    required this.backgroundImageUrl,
  });

  final BangumiSubject subject;
  final String backgroundImageUrl;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(AnimeGardenDownloadController(subject: subject));

    return GlassScaffold(
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('资源', style: Theme.of(context).textTheme.titleLarge),
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
      body: CustomScrollView(
        controller: controller.scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            sliver: SliverToBoxAdapter(
              child: _SearchCard(controller: controller),
            ),
          ),
          Obx(() {
            if (controller.message.value != null) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      controller.message.value!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            final filteredResults = controller.filteredResults;
            if (filteredResults.isEmpty && controller.results.isNotEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('没有符合过滤条件的资源')),
              );
            }

            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList.separated(
                itemBuilder: (context, index) {
                  return _ResourceCard(
                    controller: controller,
                    resource: filteredResults[index],
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemCount: filteredResults.length,
              ),
            );
          }),
          Obx(() {
            if (controller.results.isEmpty ||
                (!controller.loadingMore.value && !controller.hasMore.value)) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: controller.loadingMore.value
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: controller.loadMore,
                          child: const Text('加载更多'),
                        ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.controller});

  final AnimeGardenDownloadController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GlassCard(
          useOwnLayer: true,
          padding: const EdgeInsets.all(20),
          shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
          settings: LiquidGlassSettings.figma(
            refraction: 42,
            depth: 24,
            dispersion: 8,
            frost: 5,
            glassColor: colorScheme.surface.withValues(alpha: 0.32),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(
                      Icons.download_rounded,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '从 AnimeGarden 检索资源',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller.keywordController,
                onSubmitted: (_) => controller.search(),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: Obx(
                    () => controller.loading.value
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            onPressed: controller.search,
                            icon: const Icon(Icons.arrow_forward_rounded),
                            tooltip: '检索',
                          ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Constants.radius),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ResourceFilters(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceFilters extends StatelessWidget {
  const _ResourceFilters({required this.controller});

  final AnimeGardenDownloadController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final range = controller.sizeRange.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '大小 ${range.start.toStringAsFixed(0)} GB - ${range.end.toStringAsFixed(0)} GB',
          ),
          RangeSlider(
            values: range,
            min: 0,
            max: 50,
            divisions: 50,
            labels: RangeLabels(
              '${range.start.toStringAsFixed(0)} GB',
              '${range.end.toStringAsFixed(0)} GB',
            ),
            onChanged: controller.setSizeRange,
          ),
          const SizedBox(height: 8),
          Text('分辨率', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: ['1080p', '2k', '4k'].map((resolution) {
              return FilterChip(
                label: Text(resolution),
                selected: controller.selectedResolutions.contains(resolution),
                onSelected: (_) => controller.toggleResolution(resolution),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text('编码格式', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: ['H.264/AVC', 'H.265/HEVC', 'AV1'].map((codec) {
              return FilterChip(
                label: Text(codec),
                selected: controller.selectedCodecs.contains(codec),
                onSelected: (_) => controller.toggleCodec(codec),
              );
            }).toList(),
          ),
        ],
      );
    });
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.controller, required this.resource});

  final AnimeGardenDownloadController controller;
  final AnimeGardenResource resource;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GlassCard(
          useOwnLayer: true,
          padding: const EdgeInsets.all(16),
          shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
          settings: LiquidGlassSettings.figma(
            refraction: 36,
            depth: 20,
            dispersion: 6,
            frost: 4,
            glassColor: colorScheme.surface.withValues(alpha: 0.28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resource.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (resource.displayGroup.isNotEmpty)
                    _ResourceChip(
                      icon: Icons.groups_outlined,
                      label: resource.displayGroup,
                    ),
                  if (resource.displaySize.isNotEmpty)
                    _ResourceChip(
                      icon: Icons.storage_outlined,
                      label: resource.displaySize,
                    ),
                  if (resource.createdAt != null)
                    _ResourceChip(
                      icon: Icons.schedule_outlined,
                      label: resource.createdAt!
                          .toLocal()
                          .toString()
                          .split('.')
                          .first,
                    ),
                  if (resource.provider.isNotEmpty)
                    _ResourceChip(
                      icon: Icons.cloud_outlined,
                      label: resource.provider,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: resource.downloadLink.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: resource.downloadLink),
                              );
                              Get.snackbar('已复制', '下载链接已复制到剪贴板');
                            },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('复制链接'),
                    ),
                    Obx(() {
                      final adding = controller.addingResourceIds.contains(
                        resource.id,
                      );
                      return FilledButton.icon(
                        onPressed:
                            controller.addingAnime ||
                                resource.downloadLink.isEmpty
                            ? null
                            : () => controller.addAnimeWithResource(resource),
                        icon: adding
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_rounded),
                        label: Text(adding ? '添加中' : '添加 Anime'),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceChip extends StatelessWidget {
  const _ResourceChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.all(Constants.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colorScheme.primary),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
