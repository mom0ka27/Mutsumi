import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../player/extension/duration.dart';
import '../../../core/extensions/build_context.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/media_summary_card.dart';
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
  var _showingError = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    try {
      await store.refresh();
    } catch (error) {
      unawaited(_showErrorDialog(error));
    }
  }

  Future<void> _showErrorDialog(Object error) async {
    if (_showingError || !mounted) {
      return;
    }
    _showingError = true;
    await showErrorDialog(
      title: '加载 Anime 失败',
      message: errorMessageOf(error),
      error: error,
    );
    _showingError = false;
  }

  Future<void> _showCreateSeriesDialog() async {
    final nameController = TextEditingController();
    final selectedIds = <int>{};
    try {
      final created = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('新建 Series'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Series 名称'),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: store.ungroupedAnimes.map((anime) {
                        return CheckboxListTile(
                          value: selectedIds.contains(anime.id),
                          title: Text(anime.displayName),
                          subtitle: anime.originalName.isEmpty
                              ? null
                              : Text(anime.originalName),
                          onChanged: (selected) => setDialogState(() {
                            if (selected == true) {
                              selectedIds.add(anime.id);
                            } else {
                              selectedIds.remove(anime.id);
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
                onPressed: selectedIds.length < 2
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) return;
                        try {
                          await store.createSeries(
                            name: name,
                            animeIds: selectedIds.toList(),
                          );
                          if (context.mounted) Get.back(result: true);
                        } catch (error) {
                          if (context.mounted) Get.back(result: false);
                          unawaited(_showErrorDialog(error));
                        }
                      },
                child: const Text('新建'),
              ),
            ],
          ),
        ),
      );
      if (created == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Series 已新建')),
        );
      }
    } finally {
      nameController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(() {
      final ungrouped = store.ungroupedAnimes;
      final itemCount = store.series.length + ungrouped.length;
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: Text('库内容 ${store.animes.length}'),
          actions: [
            IconButton(
              tooltip: '新建 Series',
              onPressed: ungrouped.length < 2 ? null : _showCreateSeriesDialog,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: store.isLoading.value
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: itemCount == 0
                    ? ListView(
                        padding: context.homeContentPadding(horizontal: 24),
                      )
                    : ListView.separated(
                        padding: context.homeContentPadding(),
                        itemBuilder: (context, index) {
                          if (index < store.series.length) {
                            return _SeriesCard(
                              series: store.series[index],
                              refresh: _refresh,
                            );
                          }
                          return _AnimeCard(
                            anime: ungrouped[index - store.series.length],
                            refresh: _refresh,
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

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.series, required this.refresh});

  final SeriesRead series;
  final Future<void> Function() refresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
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
