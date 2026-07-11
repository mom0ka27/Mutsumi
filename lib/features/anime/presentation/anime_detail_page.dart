import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../data/anime_service.dart';
import 'anime_play_page.dart';

class AnimeDetailPage extends StatefulWidget {
  const AnimeDetailPage({super.key, required this.animeId, this.initialAnime});

  final int animeId;
  final AnimeRead? initialAnime;

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage> {
  final _animeService = AnimeService();
  late final Future<AnimeRead> _future;

  @override
  void initState() {
    super.initState();
    _future = _animeService.getAnime(widget.animeId);
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initialAnime;
    return FutureBuilder<AnimeRead>(
      future: _future,
      initialData: initial,
      builder: (context, snapshot) {
        final anime = snapshot.data ?? initial;
        if (anime == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return GlassPage(
          enableBackgroundSampling: false,
          background: _DetailBackground(anime: anime),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(anime.displayName),
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
            ),
            body: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  sliver: SliverToBoxAdapter(child: _DetailCard(anime: anime)),
                ),
                if (snapshot.connectionState != ConnectionState.done)
                  const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
            floatingActionButton: anime.episodes.isEmpty
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => Get.to(
                      () => AnimePlayPage(
                        anime: anime,
                        episodes: anime.episodes,
                        initialEpisode: _initialEpisode(anime),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('播放'),
                  ),
          ),
        );
      },
    );
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
}

class _DetailBackground extends StatelessWidget {
  const _DetailBackground({required this.anime});

  final AnimeRead anime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.tertiaryContainer.withValues(alpha: 0.85),
                colorScheme.surface,
                colorScheme.primaryContainer.withValues(alpha: 0.72),
              ],
            ),
          ),
        ),
        if (anime.imageUrl.isNotEmpty)
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 520,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                child: CachedNetworkImage(
                  imageUrl: anime.imageUrl,
                  fit: BoxFit.fitHeight,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.46, 0.82, 1],
              colors: [
                Colors.black.withValues(alpha: 0.08),
                colorScheme.surface.withValues(alpha: 0.18),
                colorScheme.surface.withValues(alpha: 0.78),
                colorScheme.surface,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.anime});

  final AnimeRead anime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = anime.watchProgress;
    final progressEpisode = _progressEpisode(anime);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final cover = _CoverImage(anime: anime);
                final content = _TitleAndMeta(anime: anime);
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [cover, const SizedBox(height: 16), content],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cover,
                          const SizedBox(width: 20),
                          Expanded(child: content),
                        ],
                      );
              },
            ),
            if (progressEpisode != null && progress != null) ...[
              const SizedBox(height: 22),
              Text('上次观看', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '第 ${progressEpisode.index} 集 · ${progressEpisode.displayName} · ${_formatDuration(progress.position)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (anime.summary.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('简介', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                anime.summary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            if (anime.tags.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('标签', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: anime.tags.take(16).map((tag) {
                  return _InfoChip(icon: Icons.sell_outlined, label: tag);
                }).toList(),
              ),
            ],
            if (anime.infobox.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('信息', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...anime.infobox.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          item.key,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(child: Text(item.value)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  AnimeEpisodeRead? _progressEpisode(AnimeRead anime) {
    final episodeId = anime.watchProgress?.episodeId;
    if (episodeId == null) {
      return null;
    }
    for (final episode in anime.episodes) {
      if (episode.id == episodeId) {
        return episode;
      }
    }
    return null;
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.anime});

  final AnimeRead anime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.all(Constants.radius),
      child: SizedBox(
        width: 180,
        height: 252,
        child: anime.imageUrl.isEmpty
            ? ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : CachedNetworkImage(imageUrl: anime.imageUrl, fit: BoxFit.cover),
      ),
    );
  }
}

class _TitleAndMeta extends StatelessWidget {
  const _TitleAndMeta({required this.anime});

  final AnimeRead anime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          anime.displayName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (anime.originalName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            anime.originalName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (anime.score > 0)
              _InfoChip(
                icon: Icons.star_rounded,
                label: anime.score.toStringAsFixed(1),
              ),
            if (anime.rank > 0)
              _InfoChip(
                icon: Icons.emoji_events_outlined,
                label: '#${anime.rank}',
              ),
            if (anime.episodes.isNotEmpty)
              _InfoChip(
                icon: Icons.movie_filter_outlined,
                label: '${anime.episodes.length} 集',
              ),
            if (anime.airDate.isNotEmpty)
              _InfoChip(
                icon: Icons.calendar_month_outlined,
                label: anime.airDate,
              ),
            if (anime.platform.isNotEmpty)
              _InfoChip(icon: Icons.tv_outlined, label: anime.platform),
          ],
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

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

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    return '${duration.inHours}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
