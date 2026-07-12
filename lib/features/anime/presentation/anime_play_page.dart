import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../player/controller.dart';
import '../../../player/model/video.dart';
import '../../../player/model/danmaku.dart';
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

class _AnimePlayPageState extends State<AnimePlayPage>
    with WidgetsBindingObserver {
  final _animeService = AnimeService();
  final controller = IndexPlayerController();
  final currentIndex = 0.obs;
  Timer? _progressTimer;
  StreamSubscription<String>? _errorSubscription;
  bool _disposed = false;
  bool _showingError = false;

  AnimeEpisodeRead get _episode => widget.episodes[currentIndex.value];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    WidgetsBinding.instance.addObserver(this);
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
    final brightness = Theme.of(context).brightness;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: brightness,
      ),
    );
    controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _errorSubscription?.cancel();
    _saveProgress();
    super.dispose();
    _disposed = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        controller.isFullScreen.value &&
        !controller.disposed) {
      controller.restoreFullscreenOrientation();
    }
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
          danmakuProvider: DandanPlayDanmakuProvider(
            fileHash: episode.fileHash,
            fileName: episode.filename,
          ),
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

  Future<void> _showPlayerError(String message) async {
    if (_disposed || _showingError || message.trim().isEmpty) {
      return;
    }
    _showingError = true;
    await showErrorDialog(title: '播放出错', message: message);
    _showingError = false;
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
      if (fullScreen) {
        return Material(
          child: ColoredBox(
            color: Colors.black,
            child: IndexPlayer(controller),
          ),
        );
      }
      return GlassScaffold(
        enableBackgroundSampling: true,
        background: const AppGlassBackground(),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ColoredBox(
              color: Colors.black,
              child: SafeArea(bottom: false, child: IndexPlayer(controller)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Obx(() {
                final episode = _episode;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.anime.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '第 ${episode.index} 集 · ${episode.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: 18),
                    Obx(() {
                      final selectedIndex = currentIndex.value;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(widget.episodes.length, (
                            index,
                          ) {
                            final episode = widget.episodes[index];
                            final selected = index == selectedIndex;
                            return Padding(
                              padding: EdgeInsets.only(
                                right: index == widget.episodes.length - 1
                                    ? 0
                                    : 10,
                              ),
                              child: _EpisodeTile(
                                episode: episode,
                                selected: selected,
                                onTap: selected
                                    ? null
                                    : () async {
                                        await _saveProgress();
                                        currentIndex.value = index;
                                      },
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                  ],
                );
              }),
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
      child: GlassContainer(
        width: 160,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '第 ${episode.index} 集',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w900 : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              episode.displayName,
              maxLines: 1,
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
