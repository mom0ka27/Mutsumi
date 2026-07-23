import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mutsumi/constants.dart';

import '../../../player/extension/duration.dart';
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(() {
      if (store.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: store.animes.isEmpty
            ? ListView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  Constants.homeTopPadding,
                  24,
                  Constants.bottomPadding,
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  20,
                  Constants.homeTopPadding,
                  20,
                  Constants.bottomPadding,
                ),
                itemBuilder: (context, index) =>
                    _AnimeCard(anime: store.animes[index], refresh: _refresh),
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemCount: store.animes.length,
              ),
      );
    });
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
