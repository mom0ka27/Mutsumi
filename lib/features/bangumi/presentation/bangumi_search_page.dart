import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/media_summary_card.dart';
import '../data/bangumi_repository.dart';
import 'bangumi_detail_page.dart';
import 'bangumi_search_controller.dart';

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
    return MediaSummaryCard(
      imageUrl: subject.imageUrl,
      title: subject.displayName,
      subtitle: subject.originalName,
      summary: subject.summary,
      chips: [
        if (subject.score > 0)
          MediaInfoChip(
            icon: Icons.star_rounded,
            label: subject.score.toStringAsFixed(1),
          ),
        if (subject.episodeCount > 0)
          MediaInfoChip(
            icon: Icons.movie_filter_outlined,
            label: '${subject.episodeCount} 话',
          ),
        if (subject.airDate.isNotEmpty)
          MediaInfoChip(
            icon: Icons.calendar_month_outlined,
            label: subject.airDate,
          ),
      ],
      onTap: () => Get.to(() => BangumiDetailPage(subject: subject)),
    );
  }
}
