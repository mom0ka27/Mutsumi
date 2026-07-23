import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/media_summary_card.dart';
import '../../../core/widgets/app_glass_settings.dart';
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
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = Get.put(
      BangumiSearchController(animeListStore: widget.store),
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, Constants.homeTopPadding, 20, 16),
          sliver: SliverToBoxAdapter(
            child: _SearchHeader(controller: controller),
          ),
        ),
        Obx(() {
          return SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, Constants.bottomPadding),
            sliver: SliverList.separated(
              itemBuilder: (context, index) {
                final subject = controller.results[index];
                final existingAnime = controller.existingAnimeMap[subject.id];
                return _SubjectCard(
                  key: ValueKey('bangumi-subject-${subject.id}'),
                  subject: subject,
                  existingAnime: existingAnime,
                );
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
            ],
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
          );
        } else {
          Get.to(() => BangumiDetailPage(subject: subject));
        }
      },
    );
  }
}
