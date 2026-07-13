import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/formatters/duration_formatter.dart';
import '../../../core/widgets/media_summary_card.dart';
import '../data/anime_service.dart';
import 'anime_detail_page.dart';

class AnimeHomeView extends StatefulWidget {
  const AnimeHomeView({super.key});

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
              return Center(child: Text('加载 Anime 失败\n${snapshot.error}'));
            }

            final animes = snapshot.data ?? const <AnimeRead>[];
            if (animes.isEmpty) {
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  Constants.topPadding,
                  24,
                  Constants.bottomPadding,
                ),
              );
            }

            return ListView.separated(
              padding: EdgeInsets.fromLTRB(
                20,
                Constants.topPadding,
                20,
                Constants.bottomPadding,
              ),
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
    final progress = anime.watchProgress;
    final lastEpisode = progress?.episodeId == null
        ? null
        : anime.episodes.firstWhereOrNull(
            (episode) => episode.id == progress!.episodeId,
          );

    return MediaSummaryCard(
      imageUrl: anime.imageUrl,
      heroTag: 'anime-cover-${anime.id}',
      title: anime.displayName,
      subtitle: anime.originalName,
      summary: anime.summary,
      chips: [
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
            label:
                '上次 ${lastEpisode.index} · ${formatDuration(progress!.position)}',
          ),
      ],
      onTap: () async {
        final deleted = await Get.to<bool>(
          () => AnimeDetailPage(animeId: anime.id, initialAnime: anime),
        );
        if (deleted == true) {
          await onDeleted();
        }
      },
    );
  }
}
