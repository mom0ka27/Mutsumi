import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/player/extension/duration.dart';
import '../../../core/extensions/build_context.dart';

import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/window/playback_window.dart';
import '../../../core/widgets/media_detail_overview.dart';
import '../../../app/page_bindings.dart';
import '../data/anime_service.dart';
import 'anime_detail_controller.dart';
import 'anime_play_page.dart';

class AnimeDetailPage extends StatefulWidget {
  const AnimeDetailPage({super.key, required this.animeId, this.initialAnime});

  final int animeId;
  final AnimeRead? initialAnime;

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage> {
  final _controller = Get.find<AnimeDetailController>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final anime = _controller.anime.value;
      if (anime == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      return GlassScaffold(
        topEdgeFade: true,
        bottomEdgeFade: false,
        background: MediaDetailBackground(
          imageUrl: anime.imageUrl,
          blurSigma: 24,
          showGradientWithoutImage: true,
        ),
        statusBarStyle: GlassStatusBarStyle.light,
        edgeToEdge: true,
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
            Obx(
              () => _controller.refreshing.value
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : GlassButton(
                      width: 40,
                      height: 40,
                      iconSize: 20,
                      icon: const Icon(Icons.refresh_rounded),
                      label: '刷新番剧信息',
                      onTap: _controller.refreshAnime,
                    ),
            ),
            SizedBox(width: 2),
            Obx(
              () => _controller.deleting.value
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : GlassButton(
                      width: 40,
                      height: 40,
                      iconSize: 20,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: '删除番剧',
                      onTap: () => _deleteAnime(anime),
                    ),
            ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: context.pageContentPadding(bottom: 120),
              sliver: SliverToBoxAdapter(
                child: MediaDetailOverview(
                  data: _overviewData(anime),
                  heroTag: 'cover-${anime.bangumiId}',
                  beforeSummary: _watchProgress(anime),
                ),
              ),
            ),
            if (_controller.loading.value)
              const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
        floatingActionButton: anime.episodes.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () async {
                  final windowLease = await PlaybackWindow.enter();
                  try {
                    await Get.to(
                      () => AnimePlayPage(
                        anime: anime,
                        episodes: anime.episodes,
                        initialEpisode: _initialEpisode(anime),
                      ),
                      binding: AnimePlayBinding(
                        anime: anime,
                        episodes: anime.episodes,
                        initialEpisode: _initialEpisode(anime),
                      ),
                    );
                  } finally {
                    await windowLease.release();
                  }
                  await _controller.load();
                },
                label: Text("播放"),
                icon: const Icon(Icons.play_arrow),
              ),
      );
    });
  }

  int _initialEpisode(AnimeRead anime) {
    final progressEpisodeId = anime.watchProgress?.episodeId;
    if (progressEpisodeId != null) {
      for (final episode in anime.episodes) {
        if (episode.id == progressEpisodeId) {
          return anime.episodes.indexOf(episode);
        }
      }
    }
    return 0;
  }

  MediaDetailOverviewData _overviewData(AnimeRead anime) {
    return MediaDetailOverviewData(
      title: anime.displayName,
      originalTitle: anime.originalName,
      imageUrl: anime.imageUrl,
      metadata: [
        if (anime.score > 0)
          MediaDetailMetadata(
            icon: Icons.star_rounded,
            label: anime.score.toStringAsFixed(1),
          ),
        if (anime.rank > 0)
          MediaDetailMetadata(
            icon: Icons.emoji_events_outlined,
            label: '#${anime.rank}',
          ),
        if (anime.episodes.isNotEmpty)
          MediaDetailMetadata(
            icon: Icons.movie_filter_outlined,
            label: '${anime.episodes.length} 集',
          ),
        if (anime.airDate.isNotEmpty)
          MediaDetailMetadata(
            icon: Icons.calendar_month_outlined,
            label: anime.airDate,
          ),
        if (anime.platform.isNotEmpty)
          MediaDetailMetadata(icon: Icons.tv_outlined, label: anime.platform),
      ],
      summary: anime.summary,
      tags: anime.tags,
      infoItems: anime.infobox
          .map(
            (item) => MediaDetailInfoItem(label: item.key, value: item.value),
          )
          .toList(),
    );
  }

  Widget? _watchProgress(AnimeRead anime) {
    final episodeId = anime.watchProgress?.episodeId;
    final progress = anime.watchProgress;
    if (episodeId == null || progress == null) {
      return null;
    }
    final episode = anime.episodes.firstWhereOrNull(
      (episode) => episode.id == episodeId,
    );
    if (episode == null) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('上次观看', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '第 ${episode.index} 集 · ${episode.displayName} · ${progress.position.str}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAnime(AnimeRead anime) async {
    final colorScheme = Theme.of(context).colorScheme;
    var deleteFiles = true;

    final confirmed = await showAppDialog<bool>(
      StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('删除番剧'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定删除"${anime.displayName}"吗？此操作无法撤销。'),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: !deleteFiles,
                      onChanged: (value) {
                        setState(() => deleteFiles = !(value ?? false));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('保留磁盘文件'),
                ],
              ),
            ],
          ),
          actions: [
            Builder(
              builder: (context) => TextButton(
                onPressed: () => AppDialog.dismiss(context, false),
                child: const Text('取消'),
              ),
            ),
            Builder(
              builder: (context) => FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                onPressed: () => AppDialog.dismiss(context, true),
                child: const Text('删除'),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final deleted = await _controller.deleteAnime(deleteFiles: deleteFiles);
    if (deleted) {
      Get.back(result: true);
      await showInfoDialog(
        title: '删除成功',
        message: deleteFiles
            ? '已删除"${anime.displayName}"及其下载文件'
            : '已删除"${anime.displayName}"，文件已保留',
      );
    }
  }
}
