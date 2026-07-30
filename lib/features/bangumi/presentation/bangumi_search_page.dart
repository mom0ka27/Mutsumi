import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/media_summary_card.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../../core/extensions/build_context.dart';
import '../../../app/page_bindings.dart';
import '../../anime/data/anime_list_store.dart';
import '../../anime/data/anime_service.dart';
import '../../anime/presentation/anime_detail_page.dart';
import '../data/bangumi_repository.dart';
import 'bangumi_detail_page.dart';
import 'bangumi_search_controller.dart';

class BangumiSearchView extends StatefulWidget {
  const BangumiSearchView({super.key, required this.store});

  final AnimeListStore store;

  @override
  State<BangumiSearchView> createState() => _BangumiSearchViewState();
}

class _BangumiSearchViewState extends State<BangumiSearchView>
    with AutomaticKeepAliveClientMixin {
  final _controller = Get.find<BangumiSearchController>();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final padding = context.homeContentPadding();

    return CustomScrollView(
      controller: _controller.scrollController,
      slivers: [
        SliverPadding(
          padding: padding.copyWith(bottom: 16),
          sliver: SliverToBoxAdapter(
            child: _SearchHeader(controller: _controller),
          ),
        ),
        Obx(() {
          return SliverPadding(
            padding: padding.copyWith(top: 0),
            sliver: SliverList.separated(
              itemBuilder: (context, index) {
                final subject = _controller.results[index];
                final existingAnime = _controller.existingAnimeMap[subject.id];
                return _SubjectCard(
                  key: ValueKey('bangumi-subject-${subject.id}'),
                  subject: subject,
                  existingAnime: existingAnime,
                );
              },
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemCount: _controller.results.length,
            ),
          );
        }),
        _SearchFooter(controller: _controller, padding: padding),
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
          settings: AppGlassSettings.standard(context),
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
              const SizedBox(height: 8),
              _SearchFilters(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchFilters extends StatelessWidget {
  const _SearchFilters({required this.controller});

  final BangumiSearchController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.all(Constants.radius),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.tune_rounded),
        title: const Text('类型筛选'),
        children: [
          Obx(
            () => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const {1: '书籍', 2: '动画', 3: '音乐', 4: '游戏', 6: '三次元'}
                  .entries
                  .map(
                    (entry) => FilterChip(
                      label: Text(entry.value),
                      selected: controller.selectedTypes.contains(entry.key),
                      onSelected: (_) => controller.toggleType(entry.key),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: controller.applyFilters,
                icon: const Icon(Icons.search_rounded),
                label: const Text('应用筛选'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchFooter extends StatelessWidget {
  const _SearchFooter({required this.controller, required this.padding});

  final BangumiSearchController controller;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (controller.loading.value || controller.results.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverPadding(
      padding: padding.copyWith(top: 18, bottom: 28),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: controller.loadingMore.value
              ? const CircularProgressIndicator()
              : controller.hasMore.value
              ? OutlinedButton.icon(
                  onPressed: controller.loadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    '加载更多（已显示 ${controller.results.length}/${controller.total.value}）',
                  ),
                )
              : Text(
                  '已显示全部 ${controller.results.length} 条结果',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({super.key, required this.subject, this.existingAnime});

  final BangumiSubject subject;
  final AnimeRead? existingAnime;

  @override
  Widget build(BuildContext context) {
    return MediaSummaryCard(
      imageUrl: subject.imageUrl,
      heroTag: 'cover-${subject.id}',
      title: subject.displayName,
      subtitle: subject.originalName,
      summary: subject.summary,
      chips: [
        if (existingAnime != null)
          MediaInfoChip(icon: Icons.check_circle_rounded, label: '已添加'),
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
      onTap: () {
        if (existingAnime != null) {
          Get.to(
            () => AnimeDetailPage(
              animeId: existingAnime!.id,
              initialAnime: existingAnime,
            ),
            binding: AnimeDetailBinding(
              animeId: existingAnime!.id,
              initialAnime: existingAnime,
            ),
          );
        } else {
          Get.to(
            () => BangumiDetailPage(subject: subject),
            binding: BangumiDetailBinding(subject: subject),
          );
        }
      },
    );
  }
}
