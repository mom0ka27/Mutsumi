import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../constants.dart';
import '../../../player/extension/duration.dart';
import '../../../core/extensions/build_context.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../../core/widgets/media_summary_card.dart';
import '../../../app/page_bindings.dart';
import '../data/anime_list_store.dart';
import '../data/anime_service.dart';
import 'anime_detail_page.dart';

class AnimeHomeView extends StatefulWidget {
  const AnimeHomeView({super.key, required this.store});

  final AnimeListStore store;

  @override
  State<AnimeHomeView> createState() => _AnimeHomeViewState();
}

class _AnimeHomeViewState extends State<AnimeHomeView>
    with AutomaticKeepAliveClientMixin {
  AnimeListStore get store => widget.store;

  @override
  bool get wantKeepAlive => true;

  Future<void> _showCreateSeriesDialog() async {
    final request = await showDialog<_CreateSeriesRequest>(
      context: context,
      builder: (_) => _CreateSeriesDialog(animes: store.ungroupedAnimes),
    );
    if (request == null) return;
    await store.createSeries(name: request.name, animeIds: request.animeIds);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(() {
      final ungrouped = store.ungroupedAnimes;
      final itemCount = store.series.length + ungrouped.length;
      return GlassScaffold(
        appBar: GlassAppBar(
          padding: EdgeInsets.symmetric(horizontal: 16),
          centerTitle: false,
          backgroundColor: Colors.transparent,
          title: Text('库内容', style: Theme.of(context).textTheme.headlineSmall),
          actions: [
            GlassButton(
              label: '新建 Series',
              onTap: _showCreateSeriesDialog,
              icon: const Icon(Icons.create_new_folder_outlined),
              width: 44,
            ),
          ],
        ),
        body: store.isLoading.value
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: store.refresh,
                child: itemCount == 0
                    ? ListView(
                        padding: context.pageContentPadding(horizontal: 356),
                      )
                    : ListView.separated(
                        padding: context.pageContentPadding(bottom: 72),
                        itemBuilder: (context, index) {
                          if (index < store.series.length) {
                            return _SeriesCard(
                              series: store.series[index],
                              refresh: store.refresh,
                            );
                          }
                          return _AnimeCard(
                            anime: ungrouped[index - store.series.length],
                            refresh: store.refresh,
                          );
                        },
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemCount: itemCount,
                      ),
              ),
      );
    });
  }
}

class _CreateSeriesRequest {
  const _CreateSeriesRequest({required this.name, required this.animeIds});

  final String name;
  final List<int> animeIds;
}

class _CreateSeriesDialog extends StatefulWidget {
  const _CreateSeriesDialog({required this.animes});

  final List<AnimeRead> animes;

  @override
  State<_CreateSeriesDialog> createState() => _CreateSeriesDialogState();
}

class _CreateSeriesDialogState extends State<_CreateSeriesDialog> {
  final _nameController = TextEditingController();
  final _selectedIds = <int>{};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();
    return AlertDialog(
      title: const Text('新建 Series'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Series 名称'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.animes.map((anime) {
                  return CheckboxListTile(
                    value: _selectedIds.contains(anime.id),
                    title: Text(anime.displayName),
                    subtitle: anime.originalName.isEmpty
                        ? null
                        : Text(anime.originalName),
                    onChanged: (selected) => setState(() {
                      if (selected == true) {
                        _selectedIds.add(anime.id);
                      } else {
                        _selectedIds.remove(anime.id);
                      }
                    }),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('取消')),
        FilledButton(
          onPressed: name.isEmpty || _selectedIds.length < 2
              ? null
              : () => Get.back(
                  result: _CreateSeriesRequest(
                    name: name,
                    animeIds: _selectedIds.toList(),
                  ),
                ),
          child: const Text('新建'),
        ),
      ],
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.series, required this.refresh});

  final SeriesRead series;
  final Future<void> Function() refresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GlassCard(
          useOwnLayer: true,
          padding: EdgeInsets.zero,
          shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
          settings: AppGlassSettings.standard(context),
          child: Material(
            color: Colors.transparent,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.video_library_outlined),
              title: Text(series.name),
              subtitle: Text('${series.animes.length} 部作品'),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: series.animes
                  .map(
                    (anime) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _AnimeCard(anime: anime, refresh: refresh),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimeCard extends StatelessWidget {
  const _AnimeCard({required this.anime, required this.refresh});

  final AnimeRead anime;
  final Future<void> Function() refresh;

  @override
  Widget build(BuildContext context) {
    final progress = anime.watchProgress;
    final lastEpisode = progress?.episodeId == null
        ? null
        : anime.episodes.firstWhereOrNull(
            (episode) => episode.id == progress!.episodeId,
          );

    return MediaSummaryCard(
      imageUrl: anime.imageUrl,
      heroTag: 'cover-${anime.bangumiId}',
      title: anime.displayName,
      subtitle: anime.originalName,
      summary: anime.summary,
      chips: [
        MediaInfoChip(
          icon: Icons.live_tv_outlined,
          label: _mediaTypeLabel(anime.mediaType),
        ),
        if (anime.score > 0)
          MediaInfoChip(
            icon: Icons.star_rounded,
            label: anime.score.toStringAsFixed(1),
          ),
        if (anime.episodes.isNotEmpty)
          MediaInfoChip(
            icon: Icons.movie_filter_outlined,
            label: '${anime.episodes.length} 集',
          ),
        if (lastEpisode != null)
          MediaInfoChip(
            icon: Icons.history_rounded,
            label: '上次 ${lastEpisode.index} · ${progress!.position.str}',
          ),
      ],
      onTap: () async {
        final deleted = await Get.to<bool>(
          () => AnimeDetailPage(animeId: anime.id, initialAnime: anime),
          binding: AnimeDetailBinding(animeId: anime.id, initialAnime: anime),
        );
        if (deleted == true) {
          await refresh();
        }
      },
    );
  }
}

String _mediaTypeLabel(String value) {
  return switch (value.toLowerCase()) {
    'tv' => 'TV',
    'movie' => '剧场版',
    'ova' => 'OVA',
    'ona' => 'ONA',
    'special' => '特别篇',
    'unknown' || '' => '未知类型',
    _ => value,
  };
}
