import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/network/app_network_error.dart';
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
    this.windowPreparedExternally = false,
  });

  final AnimeRead anime;
  final List<AnimeEpisodeRead> episodes;
  final int initialEpisode;
  final bool windowPreparedExternally;

  static const _windowChannel = MethodChannel('mutsumi/window');

  static Future<void> preparePlaybackWindow() async {
    if (Platform.isMacOS) {
      await _windowChannel.invokeMethod<void>('setPlaybackAspectRatio');
    }
  }

  static Future<void> restorePlaybackWindow() async {
    if (Platform.isMacOS) {
      await _windowChannel.invokeMethod<void>('clearPlaybackAspectRatio');
    }
  }

  @override
  State<AnimePlayPage> createState() => _AnimePlayPageState();
}

class _AnimePlayPageState extends State<AnimePlayPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _animeService = AnimeService();
  final controller = IndexPlayerController();
  final currentIndex = 0.obs;
  Timer? _progressTimer;
  StreamSubscription<String>? _errorSubscription;
  late final _WatchProgressSyncer _progressSyncer;
  bool _disposed = false;
  bool _showingError = false;
  bool _fullscreenLocked = false;
  bool _episodePanelVisible = false;
  late final AnimationController _episodePanelController;
  late final Animation<Offset> _episodePanelOffset;
  // AnimeEpisodeRead? _activeEpisode;
  var _episodeLoadGeneration = 0;

  AnimeEpisodeRead get _episode => widget.episodes[currentIndex.value];

  @override
  void initState() {
    super.initState();
    _episodePanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 240),
      animationBehavior: AnimationBehavior.preserve,
    );
    _episodePanelOffset =
        Tween<Offset>(begin: const Offset(1.08, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _episodePanelController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    if (Platform.isMacOS) {
      _fullscreenLocked = true;
      unawaited(controller.enterFullscreen());
      if (!widget.windowPreparedExternally) {
        unawaited(AnimePlayPage.preparePlaybackWindow());
      }
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
      _setCurrentEpisode(
        widget.initialEpisode.clamp(0, widget.episodes.length - 1),
        initial: true,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (Platform.isMacOS && !widget.windowPreparedExternally) {
      unawaited(AnimePlayPage.restorePlaybackWindow());
    }
    _progressTimer?.cancel();
    _errorSubscription?.cancel();
    unawaited(_saveProgress());
    if (controller.isFullScreen.value) {
      unawaited(controller.exitFullscreen());
    }
    controller.pause();
    controller.dispose();
    _episodePanelController.dispose();
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

  Future<void> _setCurrentEpisode(int index, {bool initial = false}) async {
    if (_disposed || controller.disposed) {
      return;
    }
    currentIndex.value = index;
    final loadGeneration = ++_episodeLoadGeneration;
    final episode = _episode;
    final shouldResume =
        initial && widget.anime.watchProgress?.episodeId == episode.id;
    try {
      final fileHash = await _animeService.fetchEpisodeFileHash(
        widget.anime.id,
        episode.id,
      );
      final subtitleTracks = <SubtitleTrack>[];
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
            subtitleTracks.add(SubtitleTrack(path: subtitlePath));
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
      await controller.setVideo(
        NetworkVideo(
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
        start: shouldResume ? widget.anime.watchProgress?.position : null,
      );
      await controller.loadExternalSubtitleTracks(subtitleTracks);
    } catch (error) {
      unawaited(_showPlayerError(error));
      return;
    }
    if (_disposed ||
        controller.disposed ||
        loadGeneration != _episodeLoadGeneration) {
      return;
    }
    try {
      await controller.play();
    } catch (error) {
      unawaited(_showPlayerError(error));
    }
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

  Future<void> _playNextEpisode() async {
    final nextIndex = currentIndex.value + 1;
    if (nextIndex >= widget.episodes.length) {
      return;
    }
    await _saveProgress();
    await _setCurrentEpisode(nextIndex);
  }

  void _lockFullscreenForLandscape() {
    if (_disposed || _fullscreenLocked) {
      return;
    }
    setState(() => _fullscreenLocked = true);
    if (!controller.isFullScreen.value) {
      unawaited(controller.enterFullscreen());
    }
  }

  void _toggleEpisodePanel() {
    if (_episodePanelVisible) {
      _closeEpisodePanel();
      return;
    }
    setState(() => _episodePanelVisible = true);
    _episodePanelController.forward(from: 0);
  }

  void _closeEpisodePanel() {
    if (_episodePanelVisible) {
      setState(() => _episodePanelVisible = false);
      _episodePanelController.reverse();
    }
  }

  Future<void> _selectEpisodeFromPanel(int index) async {
    if (index == currentIndex.value) {
      return;
    }
    await _saveProgress();
    await _setCurrentEpisode(index);
  }

  Future<void> _saveProgress() async {
    if (controller.disposed) {
      return;
    }
    if (widget.episodes.isEmpty ||
        currentIndex.value >= widget.episodes.length) {
      return;
    }
    final episode = _episode;

    final position = controller.state.position;
    if (position == Duration.zero) {
      return;
    }
    await _progressSyncer.enqueue(
      _WatchProgressSnapshot(episodeId: episode.id, position: position),
    );
    widget.anime.watchProgress = WatchProgressRead(
      episodeId: episode.id,
      position: position,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.episodes.isEmpty) {
        return const Center(child: Text('暂无剧集'));
      }
      final mobile = Platform.isAndroid || Platform.isIOS;
      final requiresLockedFullscreen = mobile && context.isLandscape;
      if (requiresLockedFullscreen && !_fullscreenLocked) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _lockFullscreenForLandscape(),
        );
      }
      final fullScreen = controller.isFullScreen.value;
      if (fullScreen) {
        return PopScope(
          canPop: !_episodePanelVisible,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _episodePanelVisible) {
              _closeEpisodePanel();
            }
          },
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IndexPlayer(
                    controller,
                    useOverlay: true,
                    fullscreenLocked: _fullscreenLocked,
                    onToggleEpisodes: _toggleEpisodePanel,
                    onNextEpisode:
                        currentIndex.value < widget.episodes.length - 1
                        ? () => unawaited(_playNextEpisode())
                        : null,
                  ),
                ),
                if (!_episodePanelVisible)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: 24,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) < -200) {
                          _toggleEpisodePanel();
                        }
                      },
                    ),
                  ),
                _episodePanel(context),
              ],
            ),
          ),
        );
      }
      return GlassScaffold(
        enableBackgroundSampling: true,
        background: const AppGlassBackground(),
        body: _portraitBody(context),
      );
    });
  }

  Widget _episodePanel(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safeArea = MediaQuery.viewPaddingOf(context);
    final compact = size.height < 500;
    final panelInset = Platform.isMacOS ? 16.0 : 10.0;
    final availableWidth = size.width - safeArea.left - safeArea.right;
    final width = (availableWidth * (Platform.isMacOS ? 0.4 : 0.42)).clamp(
      300.0,
      Platform.isMacOS ? 400.0 : 360.0,
    );
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_episodePanelVisible,
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _closeEpisodePanel(),
                child: AnimatedOpacity(
                  opacity: _episodePanelVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
            Positioned(
              top: panelInset,
              right: panelInset,
              bottom: panelInset,
              width: width,
              child: SlideTransition(
                position: _episodePanelOffset,
                child: SafeArea(
                  left: false,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Material(
                      color: Colors.transparent,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.black.withValues(alpha: 0.82),
                              Colors.black.withValues(alpha: 0.68),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 16 : 20,
                            compact ? 14 : 18,
                            compact ? 16 : 20,
                            compact ? 14 : 18,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.video_library_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '选集  ${currentIndex.value + 1} / ${widget.episodes.length}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.anime.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.white60),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _toggleEpisodePanel,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white70,
                                    ),
                                    tooltip: '关闭',
                                  ),
                                ],
                              ),
                              SizedBox(height: compact ? 12 : 16),
                              Divider(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              SizedBox(height: compact ? 10 : 14),
                              Expanded(child: _episodePanelList()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _episodePanelList() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: widget.episodes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => Obx(
        () => _EpisodeTile(
          episode: widget.episodes[index],
          selected: index == currentIndex.value,
          onTap: index == currentIndex.value
              ? null
              : () => unawaited(_selectEpisodeFromPanel(index)),
        ),
      ),
    );
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
            child: IndexPlayer(controller, useOverlay: false),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _episodeHeader(context),
              const SizedBox(height: 18),
              _episodeSelector(vertical: false),
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

  Widget _episodeSelector({required bool vertical}) {
    return Obx(() {
      final selectedIndex = currentIndex.value;

      Widget tileAt(int index, {double? width}) {
        final selected = index == selectedIndex;
        return _EpisodeTile(
          episode: widget.episodes[index],
          selected: selected,
          width: width,
          onTap: selected
              ? null
              : () async {
                  await _saveProgress();
                  unawaited(_setCurrentEpisode(index));
                },
        );
      }

      if (vertical) {
        // 纵向时铺满右栏宽度。
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: widget.episodes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => tileAt(index),
        );
      }

      // 横向滚动条的高度取决于内容，用 Row 而不是 ListView 才能自适应高度。
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(
            widget.episodes.length,
            (index) => Padding(
              padding: EdgeInsets.only(
                right: index == widget.episodes.length - 1 ? 0 : 10,
              ),
              child: tileAt(index, width: 160),
            ),
          ),
        ),
      );
    });
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

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.selected,
    required this.onTap,
    this.width,
  });

  final AnimeEpisodeRead episode;
  final bool selected;
  final VoidCallback? onTap;

  /// 为空表示铺满可用宽度。
  final double? width;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? colorScheme.onPrimaryContainer : Colors.white;
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 3,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected ? colorScheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '第 ${episode.index} 集',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: selected ? foreground : Colors.white60,
                              fontWeight: selected ? FontWeight.w700 : null,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        episode.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: foreground,
                          fontWeight: selected ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                selected
                    ? _PlayingIndicator(color: colorScheme.primary)
                    : const Icon(
                        Icons.play_arrow_rounded,
                        size: 20,
                        color: Colors.white38,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator({required this.color});

  final Color color;

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      animationBehavior: AnimationBehavior.preserve,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final phase = _controller.value * 3;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (index) {
              final value = (phase + index * 0.72) % 3;
              final normalized = value <= 1.5 ? value / 1.5 : (3 - value) / 1.5;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  width: 3,
                  height: 5 + normalized * 12,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
