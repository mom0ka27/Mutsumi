import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../data/bangumi_repository.dart';
import 'bangumi_detail_page.dart';
import 'bangumi_search_controller.dart';

class BangumiSearchPage extends StatelessWidget {
  const BangumiSearchPage({super.key});

  static const routeName = '/bangumi/search';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GlassPage(
      enableBackgroundSampling: false,
      background: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.tertiaryContainer.withValues(alpha: 0.95),
              colorScheme.surface,
              colorScheme.primaryContainer.withValues(alpha: 0.8),
            ],
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Bangumi 搜索'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: const BangumiSearchView(),
      ),
    );
  }
}

class BangumiSearchView extends StatelessWidget {
  const BangumiSearchView({super.key, this.bottomPadding = 24});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(BangumiSearchController());

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          sliver: SliverToBoxAdapter(
            child: _SearchHeader(controller: controller),
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

          return SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding),
            sliver: SliverList.separated(
              itemBuilder: (context, index) {
                return _SubjectCard(subject: controller.results[index]);
              },
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemCount: controller.results.length,
            ),
          );
        }),
      ],
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.controller});

  final BangumiSearchController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GlassCard(
          useOwnLayer: true,
          padding: const EdgeInsets.all(22),
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
                    radius: 24,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(
                      Icons.travel_explore_rounded,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '检索番剧信息',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '从 Bangumi 搜索动画条目',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller.queryController,
                onSubmitted: controller.search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '输入番剧名称',
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
                            onPressed: () => controller.search(),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            tooltip: '搜索',
                          ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Constants.radius),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject});

  final BangumiSubject subject;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GestureDetector(
          onTap: () => Get.to(() => BangumiDetailPage(subject: subject)),
          child: GlassCard(
            useOwnLayer: true,
            padding: const EdgeInsets.only(right: 14),
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            settings: LiquidGlassSettings.figma(
              refraction: 36,
              depth: 20,
              dispersion: 6,
              frost: 4,
              glassColor: colorScheme.surface.withValues(alpha: 0.28),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.all(Constants.radius),
                    child: SizedBox(
                      width: 104,
                      child: subject.imageUrl.isEmpty
                          ? ColoredBox(
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: subject.imageUrl,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (subject.originalName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subject.originalName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (subject.score > 0)
                                InfoChip(
                                  icon: Icons.star_rounded,
                                  label: subject.score.toStringAsFixed(1),
                                ),
                              if (subject.episodeCount > 0)
                                InfoChip(
                                  icon: Icons.movie_filter_outlined,
                                  label: '${subject.episodeCount} 话',
                                ),
                              if (subject.airDate.isNotEmpty)
                                InfoChip(
                                  icon: Icons.calendar_month_outlined,
                                  label: subject.airDate,
                                ),
                            ],
                          ),
                          if (subject.summary.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              subject.summary,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.label});

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
