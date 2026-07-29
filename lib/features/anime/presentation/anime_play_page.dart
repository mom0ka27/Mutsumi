import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/network/app_network_error.dart';
import '../../../player/controller.dart';
import '../../../player/model/playlist.dart';
import '../../../player/model/video.dart';
import '../../../player/model/danmaku.dart';
import '../../../player/player.dart';
import '../data/anime_service.dart';
import 'anime_player_font.dart';

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
  late final IndexPlayerController controller;
  Timer? _progressTimer;
  StreamSubscription<String>? _errorSubscription;
  late final _WatchProgressSyncer _progressSyncer;
  bool _disposed = false;
  bool _showingError = false;
  bool _landscapeFullscreenRequested = false;
  late final Future<void> _playerFontReady;

  int get _currentIndex =>
      controller.selectedIndex.value ??
      controller.loadingIndex.value ??
      widget.initialEpisode.clamp(0, widget.episodes.length - 1);
  AnimeEpisodeRead get _episode => widget.episodes[_currentIndex];

  @override
  void initState() {
    super.initState();
    controller = IndexPlayerController(
      playlist: PlayerPlaylist(
        title: widget.anime.displayName,
        items: widget.episodes
            .map(
              (episode) => PlayerPlaylistItem(
                id: episode.id,
                number: episode.index,
                title: episode.displayName,
                initialPosition:
                    widget.anime.watchProgress?.episodeId == episode.id
                    ? widget.anime.watchProgress?.position
                    : null,
                load: () => _loadEpisodeMedia(episode),
              ),
            )
            .toList(growable: false),
      ),
      onItemLeaving: _syncProgress,
    );
    _playerFontReady = configureAnimePlayerFont(controller.player);
    if (AppPlatform.isMacOS) {
      unawaited(controller.enterFullscreen());
    }
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    WidgetsBinding.instance.addObserver(this);
    _progressSyncer = _WatchProgressSyncer(
      onSync: (snapshot) => _animeService.updateWatchProgress(
        animeId: widget.anime.id,
        episodeId: snapshot.episodeId,
        position: snapshot.position,
      ),
    );
    _errorSubscription = controller.errorStream.listen(_showPlayerError);
    if (widget.episodes.isEmpty) {
      return;
    }
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
    unawaited(
      controller.selectIndex(
        widget.initialEpisode.clamp(0, widget.episodes.length - 1),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    _errorSubscription?.cancel();
    unawaited(_saveProgress());
    if (controller.isFullScreen.value) {
      unawaited(controller.exitFullscreen());
    }
    controller.pause();
    controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveProgress());
    }
    if (state == AppLifecycleState.resumed &&
        controller.isFullScreen.value &&
        !controller.disposed) {
      controller.restoreFullscreenOrientation();
    }
  }

  Future<PlayerMedia> _loadEpisodeMedia(AnimeEpisodeRead episode) async {
    await _playerFontReady;
    final fileHash = await _animeService.fetchEpisodeFileHash(
      widget.anime.id,
      episode.id,
    );
    final subtitlePaths = <String>[];
    try {
      final subtitles = await _animeService.listEpisodeSubtitles(
        widget.anime.id,
        episode.id,
      );
      for (final subtitle in subtitles) {
        final subtitlePath = await _animeService.downloadEpisodeSubtitle(
          animeId: widget.anime.id,
          episodeId: episode.id,
          filename: subtitle.filename,
        );
        if (subtitlePath != null) {
          subtitlePaths.add(subtitlePath);
        }
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        '搜索字幕失败，将继续播放视频',
        tag: 'AnimePlayer',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return PlayerMedia(
      video: NetworkVideo(
        index: episode.index,
        uri: _animeService.episodeVideoUrl(
          animeId: widget.anime.id,
          episodeId: episode.id,
        ),
        title: episode.displayName,
        httpHeaders: _animeService.authHeaders(),
        danmakuProvider: DandanPlayDanmakuProvider(
          fileHash: fileHash,
          fileName: episode.filename,
          airDate: widget.anime.airDate,
        ),
      ),
      externalSubtitlePaths: subtitlePaths,
    );
  }

  Future<void> _showPlayerError(Object error) async {
    final message = errorMessageOf(error);
    if (_disposed || _showingError || message.trim().isEmpty) {
      return;
    }
    _showingError = true;
    await showErrorDialog(title: '播放出错', message: message, error: error);
    _showingError = false;
  }

  void _enterFullscreenForLandscape() {
    if (_disposed || controller.isFullScreen.value) {
      return;
    }
    unawaited(controller.enterFullscreen());
  }

  Future<void> _saveProgress() async {
    final snapshot = controller.currentSnapshot;
    if (controller.disposed || snapshot == null) return;
    await _syncProgress(snapshot);
  }

  Future<void> _syncProgress(PlayerPlaybackSnapshot snapshot) async {
    if (snapshot.position == Duration.zero) return;
    final episodeId = snapshot.itemId as int;
    await _progressSyncer.enqueue(
      _WatchProgressSnapshot(episodeId: episodeId, position: snapshot.position),
    );
    widget.anime.watchProgress = WatchProgressRead(
      episodeId: episodeId,
      position: snapshot.position,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.episodes.isEmpty) {
        return const Center(child: Text('暂无剧集'));
      }
      final mobile = AppPlatform.isMobile;
      final landscape = context.isLandscape;
      if (mobile && !landscape) {
        _landscapeFullscreenRequested = false;
      }
      if (mobile && landscape && !_landscapeFullscreenRequested) {
        _landscapeFullscreenRequested = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _enterFullscreenForLandscape(),
        );
      }
      final fullScreen = controller.isFullScreen.value;
      if (fullScreen) {
        return PopScope(
          canPop: !mobile,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              return;
            }
            if (mobile) {
              unawaited(controller.exitFullscreen());
            }
          },
          child: Material(
            type: MaterialType.transparency,
            child: IndexPlayer(
              controller,
              useOverlay: true,
              allowFullscreenToggle: mobile,
              closePageOnBack: !mobile,
              autoplayNextEpisode: true,
            ),
          ),
        );
      }
      return GlassScaffold(
        enableBackgroundSampling: true,
        background: const AppGlassBackground(),
        settings: AppGlassSettings.standard(context),
        body: _portraitBody(context),
      );
    });
  }

  /// 竖屏：画面在上、信息和选集在下，选集横向滚动。
  Widget _portraitBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 黑色铺到状态栏底下，画面本身再靠 SafeArea 让开。
        ColoredBox(
          color: Colors.black,
          child: SafeArea(
            bottom: false,
            child: IndexPlayer(
              controller,
              useOverlay: false,
              allowFullscreenToggle: AppPlatform.isMobile,
              autoplayNextEpisode: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _episodeHeader(context),
              const SizedBox(height: 18),
              Obx(() => _portraitEpisodeSelector(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _episodeHeader(BuildContext context) {
    return Obx(() {
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
        ],
      );
    });
  }

  Widget _portraitEpisodeSelector(BuildContext context) {
    final selectedIndex = controller.selectedIndex.value;
    final loadingIndex = controller.loadingIndex.value;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(widget.episodes.length, (index) {
          final episode = widget.episodes[index];
          final selected = index == selectedIndex;
          final loading = index == loadingIndex;
          return Padding(
            padding: EdgeInsets.only(
              right: index == widget.episodes.length - 1 ? 0 : 10,
            ),
            child: GlassCard(
              width: 160,
              padding: EdgeInsets.zero,
              shape: const LiquidRoundedSuperellipse(borderRadius: 16),
              child: InkWell(
                onTap: selected || loading
                    ? null
                    : () => unawaited(controller.selectIndex(index)),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '第 ${episode.index} 集',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              fontWeight: selected ? FontWeight.w700 : null,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        episode.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: selected ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _WatchProgressSnapshot {
  const _WatchProgressSnapshot({
    required this.episodeId,
    required this.position,
  });

  final int episodeId;
  final Duration position;

  @override
  bool operator ==(Object other) {
    return other is _WatchProgressSnapshot &&
        episodeId == other.episodeId &&
        position.inSeconds == other.position.inSeconds;
  }

  @override
  int get hashCode => Object.hash(episodeId, position.inSeconds);
}

class _WatchProgressSyncer {
  _WatchProgressSyncer({required this.onSync});

  final Future<void> Function(_WatchProgressSnapshot snapshot) onSync;
  _WatchProgressSnapshot? _pending;
  _WatchProgressSnapshot? _lastSynced;
  Future<void>? _draining;

  Future<void> enqueue(_WatchProgressSnapshot snapshot) {
    if (snapshot.position == Duration.zero ||
        snapshot == _pending ||
        snapshot == _lastSynced) {
      return _draining ?? Future.value();
    }
    _pending = snapshot;
    return _draining ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final snapshot = _pending!;
        _pending = null;
        try {
          await onSync(snapshot);
          _lastSynced = snapshot;
        } catch (error, stackTrace) {
          AppLogger.error(
            '播放进度同步失败',
            tag: 'Anime',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } finally {
      _draining = null;
    }
  }
}
