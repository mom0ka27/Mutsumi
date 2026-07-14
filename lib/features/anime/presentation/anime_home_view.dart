import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mutsumi/constants.dart';

import '../../../player/extension/duration.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/widgets/error_dialog.dart';
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
  final _animes = <AnimeRead>[].obs;
  final _isLoading = true.obs;
  var _showingError = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    _isLoading.value = true;
    try {
      _animes.value = await _animeService.listAnimes();
    } catch (error) {
      unawaited(_showErrorDialog(error));
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> _showErrorDialog(Object error) async {
    if (_showingError || !mounted) {
      return;
    }
    _showingError = true;
    final message = error is ApiBusinessException
        ? error.message
        : error.toString();
    await showErrorDialog(title: '加载 Anime 失败', message: message);
    _showingError = false;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (_isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: _animes.isEmpty
            ? ListView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  Constants.topPadding,
                  24,
                  Constants.bottomPadding,
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  20,
                  Constants.topPadding,
                  20,
                  Constants.bottomPadding,
                ),
                itemBuilder: (context, index) =>
                    _AnimeCard(anime: _animes[index], refresh: _refresh),
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemCount: _animes.length,
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
