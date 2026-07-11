import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../player/controller.dart';
import '../../../player/model/video.dart';
import '../../../player/player.dart';
import '../data/anime_service.dart';

class AnimePlayPage extends StatefulWidget {
  const AnimePlayPage({
    super.key,
    required this.anime,
    required this.episodes,
    required this.initialEpisode,
  });

  final AnimeRead anime;
  final List<AnimeEpisodeRead> episodes;
  final int initialEpisode;

  @override
  State<AnimePlayPage> createState() => _AnimePlayPageState();
}

class _AnimePlayPageState extends State<AnimePlayPage> {
  final _animeService = AnimeService();
  final controller = IndexPlayerController();
  final currentIndex = 0.obs;
  Timer? _progressTimer;
  StreamSubscription<String>? _errorSubscription;
  bool _disposed = false;

  AnimeEpisodeRead get _episode => widget.episodes[currentIndex.value];

  @override
  void initState() {
    super.initState();
    currentIndex.value = widget.initialEpisode.clamp(
      0,
      widget.episodes.length - 1,
    );
    currentIndex.listen((_) => _setCurrentEpisode());
    _setCurrentEpisode(initial: true);
    _errorSubscription = controller.stream.error.listen(_showPlayerError);
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    _errorSubscription?.cancel();
    _saveProgress();
    controller.dispose();
    super.dispose();
  }

  Future<void> _setCurrentEpisode({bool initial = false}) async {
    if (_disposed || controller.disposed) {
      return;
    }

    final episode = _episode;
    final shouldResume =
        initial && widget.anime.watchProgress?.episodeId == episode.id;
    try {
      await controller.setVideo(
        NetworkVideo(
          uri: _animeService.episodeVideoUrl(
            animeId: widget.anime.id,
            episodeId: episode.id,
          ),
          title: episode.displayName,
          httpHeaders: _animeService.authHeaders(),
        ),
        start: shouldResume ? widget.anime.watchProgress?.position : null,
      );
    } catch (error) {
      _showPlayerError(error.toString());
      return;
    }
    if (_disposed || controller.disposed) {
      return;
    }
    try {
      await controller.play();
    } catch (error) {
      _showPlayerError(error.toString());
    }
  }

  void _showPlayerError(String message) {
    if (_disposed || message.trim().isEmpty) {
      return;
    }

    Get.snackbar(
      '播放出错',
      message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _saveProgress() async {
    if (controller.disposed) {
      return;
    }

    final position = controller.state.position;
    if (position == Duration.zero) {
      return;
    }
    try {
      await _animeService.updateWatchProgress(
        animeId: widget.anime.id,
        episodeId: _episode.id,
        position: position,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final fullScreen = controller.isFullScreen.value;
      return Scaffold(
        backgroundColor: fullScreen
            ? Colors.black
            : Theme.of(context).colorScheme.surface,
        body: fullScreen
            ? IndexPlayer(controller)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: SafeArea(
                      bottom: false,
                      child: IndexPlayer(controller),
                    ),
                  ),
                  Expanded(
                    child: SafeArea(
                      top: false,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        children: [
                          SizedBox(
                            height: 92,
                            child: Obx(() {
                              final selectedIndex = currentIndex.value;
                              return ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemBuilder: (context, index) {
                                  final episode = widget.episodes[index];
                                  final selected = index == selectedIndex;
                                  return _EpisodeTile(
                                    episode: episode,
                                    selected: selected,
                                    onTap: selected
                                        ? null
                                        : () async {
                                            await _saveProgress();
                                            currentIndex.value = index;
                                          },
                                  );
                                },
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 10),
                                itemCount: widget.episodes.length,
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      );
    });
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.selected,
    required this.onTap,
  });

  final AnimeEpisodeRead episode;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 184,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '第 ${episode.index} 集',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              episode.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
