import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../data/anime_service.dart';
import 'anime_detail_page.dart';

class AnimeHomeView extends StatefulWidget {
  const AnimeHomeView({super.key, this.bottomPadding = 120});

  final double bottomPadding;

  @override
  State<AnimeHomeView> createState() => _AnimeHomeViewState();
}

class _AnimeHomeViewState extends State<AnimeHomeView> {
  final _animeService = AnimeService();
  late final Rx<Future<List<AnimeRead>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _animeService.listAnimes().obs;
  }

  Future<void> _refresh() async {
    final future = _animeService.listAnimes();
    _future.value = future;
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AnimeRead>>(
          future: _future.value,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: EdgeInsets.fromLTRB(24, 24, 24, widget.bottomPadding),
                children: [
                  Center(child: Text('加载 Anime 失败\n${snapshot.error}')),
                ],
              );
            }

            final animes = snapshot.data ?? const <AnimeRead>[];
            if (animes.isEmpty) {
              return ListView(
                padding: EdgeInsets.fromLTRB(24, 24, 24, widget.bottomPadding),
              );
            }

            return ListView.separated(
              padding: EdgeInsets.fromLTRB(20, 12, 20, widget.bottomPadding),
              itemBuilder: (context, index) =>
                  _AnimeCard(anime: animes[index], onDeleted: _refresh),
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemCount: animes.length,
            );
          },
        ),
      ),
    );
  }
}

class _AnimeCard extends StatelessWidget {
  const _AnimeCard({required this.anime, required this.onDeleted});

  final AnimeRead anime;
  final Future<void> Function() onDeleted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = anime.watchProgress;
    final lastEpisode = progress?.episodeId == null
        ? null
        : anime.episodes.firstWhereOrNull(
            (episode) => episode.id == progress!.episodeId,
          );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: GestureDetector(
          onTap: () async {
            final deleted = await Get.to<bool>(
              () => AnimeDetailPage(animeId: anime.id, initialAnime: anime),
            );
            if (deleted == true) {
              await onDeleted();
            }
          },
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
                      child: anime.imageUrl.isEmpty
                          ? ColoredBox(
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: anime.imageUrl,
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
                            anime.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (anime.originalName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              anime.originalName,
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
                              if (anime.score > 0)
                                _InfoChip(
                                  icon: Icons.star_rounded,
                                  label: anime.score.toStringAsFixed(1),
                                ),
                              if (anime.episodes.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.movie_filter_outlined,
                                  label: '${anime.episodes.length} 集',
                                ),
                              if (lastEpisode != null)
                                _InfoChip(
                                  icon: Icons.history_rounded,
                                  label:
                                      '上次 ${lastEpisode.index} · ${_formatDuration(progress!.position)}',
                                ),
                            ],
                          ),
                          if (anime.summary.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              anime.summary,
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
