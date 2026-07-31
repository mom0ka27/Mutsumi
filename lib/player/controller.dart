import 'dart:async';

import 'package:auto_orientation_v2/auto_orientation_v2.dart';
import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:ns_danmaku/ns_danmaku.dart';

import '../core/logging/app_logger.dart';
import '../core/platform/app_platform.dart';
import 'model/danmaku.dart';
import 'model/option.dart';
import 'model/playlist.dart';
import 'model/video.dart' as models;

class PlayerState {
  final _position = Duration.zero.obs;
  final _duration = Duration.zero.obs;
  final _buffering = false.obs;
  final _playing = false.obs;
  final _subtitles = Rx<List<PlayerSubtitleTrack>>(const []);
  final _subtitle = Rx<PlayerSubtitleTrack?>(null);

  Duration get position => _position.value;
  Duration get duration => _duration.value;
  bool get buffering => _buffering.value;
  bool get playing => _playing.value;
  List<PlayerSubtitleTrack> get subtitles => _subtitles.value;
  PlayerSubtitleTrack? get subtitle => _subtitle.value;

  void updatePlayback({
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool? playing,
  }) {
    if (position != null) _position.value = position;
    if (duration != null) _duration.value = duration;
    if (buffering != null) _buffering.value = buffering;
    if (playing != null) _playing.value = playing;
  }

  void updateSubtitles(
    List<PlayerSubtitleTrack> subtitles,
    PlayerSubtitleTrack? subtitle,
  ) {
    _subtitles.value = subtitles;
    _subtitle.value = subtitle;
  }

  void reset() {
    _position.value = Duration.zero;
    _duration.value = Duration.zero;
    _buffering.value = false;
    _playing.value = false;
    _subtitles.value = const [];
    _subtitle.value = null;
  }
}

class PlayerSubtitleTrack {
  const PlayerSubtitleTrack({
    required this.id,
    this.title,
    this.language,
    this.path,
    this.disabled = false,
  });

  final int id;
  final String? title;
  final String? language;
  final String? path;
  final bool disabled;
}

class IndexPlayerController {
  late final ErikaPlayer _player;
  final IndexPlayerOptions options;
  final PlayerPlaylist playlist;
  final Future<void> Function(PlayerPlaybackSnapshot snapshot)? onItemLeaving;
  final _state = PlayerState();
  final _errors = StreamController<String>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final GlobalKey _videoKey = GlobalKey();

  DanmakuController? _danmakuController;
  final Rx<bool> enableDanmaku = true.obs;
  DanmakuList? _danmakuList;
  final danmakuCount = (-1).obs;
  final danmakuEpisodeId = RxnInt();
  final Rx<bool> wantSeeking = false.obs;
  final Rx<Duration> sliderPosition = Rx(Duration.zero);
  final Rx<bool> isFullScreen = false.obs;
  final Rx<bool> debugHudEnabled = false.obs;
  final Rx<bool> debugHudUpdating = false.obs;
  final Rx<double> playbackSpeed = 1.0.obs;
  final Rx<double> volume = 1.0.obs;
  final Rx<models.Video?> _video = Rx(null);
  final RxnInt selectedIndex = RxnInt();
  final RxnInt loadingIndex = RxnInt();

  StreamSubscription<ErikaPlayerEvent>? _eventSubscription;
  Future<void>? _fullscreenTransition;
  bool _disposed = false;
  final _seeking = false.obs;
  int? _lastDanmakuSecond;
  int _videoGeneration = 0;
  bool _playbackCompleted = false;
  Completer<Duration>? _durationCompleter;
  Future<void>? _closeFuture;

  IndexPlayerController({
    required this.playlist,
    this.options = const IndexPlayerOptions(),
    this.onItemLeaving,
  }) {
    _player = ErikaPlayer(allowBackgroundPlayback: options.backgroundPlayback);
    _eventSubscription = _player.events.listen(
      _handleEventSafely,
      onError: (Object error, StackTrace stackTrace) {
        _reportError(error, stackTrace: stackTrace, message: 'Erika 事件流异常');
      },
    );
  }

  PlayerState get state => _state;
  ErikaPlayer get player => _player;
  GlobalKey get videoKey => _videoKey;
  Rx<models.Video?> get video => _video;
  bool get disposed => _disposed;
  bool get seeking => _seeking.value;
  Stream<String> get errorStream => _errors.stream;
  Stream<void> get completedStream => _completed.stream;
  bool get hasNext =>
      selectedIndex.value != null &&
      selectedIndex.value! < playlist.items.length - 1;
  bool get hasPrevious =>
      selectedIndex.value != null && selectedIndex.value! > 0;
  PlayerPlaylistItem? get selectedItem {
    final index = selectedIndex.value;
    return index == null ? null : playlist.items[index];
  }

  PlayerPlaybackSnapshot? get currentSnapshot {
    final index = selectedIndex.value;
    if (index == null) return null;
    return PlayerPlaybackSnapshot(
      itemId: playlist.items[index].id,
      index: index,
      position: _state.position,
    );
  }

  void _handleEventSafely(ErikaPlayerEvent event) {
    try {
      _handleEvent(event);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace: stackTrace, message: '处理 Erika 播放事件失败');
    }
  }

  void _reportError(
    Object error, {
    required String message,
    StackTrace? stackTrace,
    bool notify = true,
  }) {
    final trace = stackTrace ?? StackTrace.current;
    AppLogger.error(message, tag: 'Player', error: error, stackTrace: trace);
    if (notify && !_disposed && !_errors.isClosed) {
      _errors.add(error.toString());
    }
  }

  void _reportAsyncError(Future<void> future, String message) {
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _reportError(error, stackTrace: stackTrace, message: message);
        },
      ),
    );
  }

  void _handleEvent(ErikaPlayerEvent event) {
    if (_disposed) return;
    if (event.kind == ErikaEventKind.systemMediaNavigationRequested) {
      _reportAsyncError(
        _handleSystemMediaNavigation(event.systemMediaCommand),
        '处理系统媒体导航失败',
      );
      return;
    }
    if (event.kind == ErikaEventKind.positionChanged) {
      _state.updatePlayback(position: event.position);
      if (!seeking) sliderPosition.value = event.position;
    }
    if (event.kind == ErikaEventKind.durationChanged) {
      _state.updatePlayback(duration: event.duration);
      final completer = _durationCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(event.duration);
      }
    }
    _state.updatePlayback(buffering: event.buffering);
    if (event.state == ErikaPlaybackState.playing) {
      _state.updatePlayback(playing: true);
    } else if (event.state == ErikaPlaybackState.paused ||
        event.state == ErikaPlaybackState.stopped) {
      _state.updatePlayback(playing: false);
    }
    if (event.kind == ErikaEventKind.tracksChanged ||
        event.kind == ErikaEventKind.trackSelectionChanged) {
      _updateTracks(event.trackList, event.trackSelection.subtitle);
    }
    if (event.error != null && event.error!.isNotEmpty) {
      AppLogger.error(
        'Erika 播放器报告错误',
        tag: 'Player',
        error: event.error!,
        stackTrace: StackTrace.current,
      );
      _errors.add(event.error!);
    }
    if (event.state == ErikaPlaybackState.stopped &&
        !_playbackCompleted &&
        _state.duration > Duration.zero &&
        _state.position >=
            _state.duration - const Duration(milliseconds: 500)) {
      _playbackCompleted = true;
      _completed.add(null);
    }
    _pushDanmaku(event.position);
  }

  Future<void> _handleSystemMediaNavigation(
    ErikaSystemMediaCommand? command,
  ) async {
    if (_disposed || loadingIndex.value != null) return;
    switch (command) {
      case ErikaSystemMediaCommand.previous:
        await previous();
      case ErikaSystemMediaCommand.next:
        await next();
      case null:
        break;
    }
  }

  Future<void> _syncSystemMediaNavigation({required bool switching}) {
    final index = selectedIndex.value;
    return _player.setSystemMediaNavigation(
      previousEnabled: !switching && index != null && index > 0,
      nextEnabled:
          !switching && index != null && index < playlist.items.length - 1,
    );
  }

  void _updateTracks(List<ErikaTrackInfo> tracks, int? selectedId) {
    final subtitles = [
      const PlayerSubtitleTrack(id: -1, disabled: true),
      ...tracks
          .where((track) => track.kind == ErikaTrackKind.subtitle)
          .map(
            (track) => PlayerSubtitleTrack(
              id: track.id,
              title: track.title,
              language: track.language,
            ),
          ),
    ];
    final subtitle = subtitles.firstWhere(
      (track) => track.id == (selectedId ?? -1),
      orElse: () => subtitles.first,
    );
    _state.updateSubtitles(subtitles, subtitle);
  }

  void _pushDanmaku(Duration position) {
    final second = position.inSeconds;
    final controller = _danmakuController;
    final list = _danmakuList;
    if (controller == null ||
        list == null ||
        seeking ||
        (_lastDanmakuSecond != null && second <= _lastDanmakuSecond!) ||
        !controller.running) {
      return;
    }
    _lastDanmakuSecond = second;
    controller.addItems(list.getDanmakus(second));
  }

  Future<void> selectIndex(int index) async {
    if (_disposed || index < 0 || index >= playlist.items.length) return;
    if (index == selectedIndex.value || index == loadingIndex.value) return;
    final generation = ++_videoGeneration;
    final previousIndex = selectedIndex.value;
    final snapshot = currentSnapshot;
    loadingIndex.value = index;
    _reportAsyncError(
      _syncSystemMediaNavigation(switching: true),
      '同步系统媒体导航状态失败',
    );
    if (snapshot != null && snapshot.position > Duration.zero) {
      await onItemLeaving?.call(snapshot);
      if (_disposed || generation != _videoGeneration) return;
    }
    try {
      final item = playlist.items[index];
      final media = await item.load();
      if (_disposed || generation != _videoGeneration) return;
      selectedIndex.value = null;
      await _openMedia(media, generation, start: item.initialPosition);
      if (_disposed || generation != _videoGeneration) return;
      selectedIndex.value = index;
      await play();
      _reportAsyncError(
        _syncSystemMediaNavigation(switching: false),
        '同步系统媒体导航状态失败',
      );
    } catch (error) {
      if (!_disposed && generation == _videoGeneration) {
        selectedIndex.value = previousIndex;
        _reportError(error, message: '切换播放集失败', notify: true);
      }
    } finally {
      if (!_disposed && generation == _videoGeneration) {
        loadingIndex.value = null;
        _reportAsyncError(
          _syncSystemMediaNavigation(switching: false),
          '同步系统媒体导航状态失败',
        );
      }
    }
  }

  Future<void> next() async {
    final index = selectedIndex.value;
    if (index != null && index < playlist.items.length - 1) {
      await selectIndex(index + 1);
    }
  }

  Future<void> previous() async {
    final index = selectedIndex.value;
    if (index != null && index > 0) {
      await selectIndex(index - 1);
    }
  }

  Future<void> _openMedia(
    PlayerMedia media,
    int generation, {
    Duration? start,
  }) async {
    final video = media.video;
    this.video.value = video;
    _playbackCompleted = false;
    _resetPlaybackState();
    _danmakuController?.clear();
    _resetDanmakuSecond();
    _danmakuList = null;
    danmakuCount.value = 0;
    danmakuEpisodeId.value = null;
    final durationCompleter = Completer<Duration>();
    _durationCompleter = durationCompleter;
    try {
      await _player.open(
        video.uri.toString(),
        httpHeaders: video is models.NetworkVideo ? video.httpHeaders : null,
        metadata: ErikaMediaMetadata(
          title: video.title,
          artist: playlist.title,
          artwork: video.artwork,
        ),
      );
      if (generation != _videoGeneration || _disposed) return;
      await durationCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => _state.duration,
      );
    } finally {
      if (identical(_durationCompleter, durationCompleter)) {
        _durationCompleter = null;
      }
    }
    if (generation != _videoGeneration || _disposed) return;
    if (start != null && start > Duration.zero) {
      await _player.seek(start);
    }
    if (video.subtitleUri != null) {
      await _player.addExternalSubtitle(video.subtitleUri!);
      if (generation != _videoGeneration || _disposed) return;
    }
    for (final path in media.externalSubtitlePaths) {
      await _player.addExternalSubtitle(path);
      if (generation != _videoGeneration || _disposed) return;
    }
    if (media.externalSubtitlePaths.isNotEmpty) {
      await _selectPreferredExternalSubtitle();
      if (generation != _videoGeneration || _disposed) return;
    }
    final provider = video.danmakuProvider;
    if (provider != null) {
      _reportAsyncError(
        provider.getDanmakuList().then((result) {
          if (!_disposed && generation == _videoGeneration) {
            _danmakuList = result.list;
            danmakuCount.value = result.count;
            danmakuEpisodeId.value = result.episodeId;
            _resetDanmakuSecond();
            _pushDanmaku(_state.position);
          }
        }),
        '弹幕加载失败',
      );
    }
  }

  void _resetPlaybackState() {
    _state.reset();
    sliderPosition.value = Duration.zero;
  }

  void setDanmakuController(DanmakuController controller) {
    if (!_disposed) _danmakuController = controller;
  }

  void clearDanmakuController(DanmakuController controller) {
    if (identical(_danmakuController, controller)) _danmakuController = null;
  }

  void toggleDanmaku() {
    enableDanmaku.toggle();
  }

  Future<void> refreshDanmaku() async {
    final provider = _video.value?.danmakuProvider;
    if (_disposed || provider == null) return;
    final generation = _videoGeneration;
    _danmakuController?.clear();
    late final DanmakuLoadResult result;
    try {
      result = await provider.getDanmakuList();
    } catch (error, stackTrace) {
      _reportError(error, stackTrace: stackTrace, message: '刷新弹幕失败');
      rethrow;
    }
    if (!_disposed && generation == _videoGeneration) {
      _danmakuList = result.list;
      danmakuCount.value = result.count;
      danmakuEpisodeId.value = result.episodeId;
      _resetDanmakuSecond();
    }
  }

  Future<void> play() async {
    if (_disposed || _state.playing) return;
    await _player.play();
    _danmakuController?.resume();
  }

  Future<void> pause() async {
    if (_disposed || !_state.playing) return;
    _danmakuController?.pause();
    await _player.pause();
  }

  Future<void> togglePlayback() => _state.playing ? pause() : play();

  void beginSeeking() {
    if (!_disposed) {
      _seeking.value = true;
      wantSeeking.value = true;
    }
  }

  void updateSeekingPosition(Duration position) {
    if (_disposed) return;
    sliderPosition.value = position < Duration.zero
        ? Duration.zero
        : position > _state.duration
        ? _state.duration
        : position;
  }

  Future<void> endSeeking([Duration? position]) async {
    if (position != null) updateSeekingPosition(position);
    await seek(sliderPosition.value);
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    _seeking.value = true;
    wantSeeking.value = false;
    _danmakuController?.clear();
    _resetDanmakuSecond();
    final target = position < Duration.zero ? Duration.zero : position;
    try {
      await _player.seek(target);
    } finally {
      _seeking.value = false;
    }
    _resetDanmakuSecond();
    _pushDanmaku(target);
  }

  Future<void> seekBy(Duration offset) async {
    if (_disposed) return;
    final target = _state.position + offset;
    final position = target < Duration.zero
        ? Duration.zero
        : target > _state.duration
        ? _state.duration
        : target;
    _seeking.value = true;
    _danmakuController?.clear();
    _resetDanmakuSecond();
    try {
      await _player.seek(position);
    } finally {
      _seeking.value = false;
    }
    _resetDanmakuSecond();
    _pushDanmaku(position);
  }

  Future<void> adjustVolume(double delta) async {
    if (_disposed) return;
    final previous = volume.value;
    final value = (volume.value + delta).clamp(0.0, 1.0).toDouble();
    if (value == previous) return;
    volume.value = value;
    try {
      await _player.setVolume(value);
    } catch (error, stackTrace) {
      if (!_disposed && volume.value == value) volume.value = previous;
      _reportError(error, stackTrace: stackTrace, message: '调整播放器音量失败');
      rethrow;
    }
  }

  Future<void> setSpeed(double rate) async {
    if (_disposed || playbackSpeed.value == rate) return;
    await _player.setPlaybackRate(rate);
    if (!_disposed) playbackSpeed.value = rate;
  }

  Future<void> setSubtitleTrack(PlayerSubtitleTrack track) async {
    if (!_disposed) {
      await _player.selectSubtitleTrack(track.disabled ? null : track.id);
    }
  }

  Future<void> _selectPreferredExternalSubtitle() async {
    final available = await _player.tracks();
    final candidates = available.where(
      (track) => track.kind == ErikaTrackKind.subtitle,
    );
    final selected = candidates
        .where((track) => _simplifiedChineseScore(track) > 0)
        .toList();
    if (selected.isNotEmpty) {
      await _player.selectSubtitleTrack(selected.first.id);
    }
  }

  int _simplifiedChineseScore(ErikaTrackInfo track) {
    final value = [track.title, track.language]
        .whereType<String>()
        .join(' ')
        .toLowerCase()
        .replaceAll(RegExp(r'[-_ ]'), '');
    if (value.contains('简体') ||
        value.contains('简中') ||
        value.contains('simplified')) {
      return 100;
    }
    if (value.contains('zhhans') ||
        value.contains('zhcn') ||
        value.contains('chs')) {
      return 90;
    }
    return 0;
  }

  Future<void> enterFullscreen() async {
    if (_disposed || isFullScreen.value) return;
    await (_fullscreenTransition ??= _enterFullscreen());
  }

  Future<void> exitFullscreen() async {
    if (_disposed || !isFullScreen.value) return;
    await (_fullscreenTransition ??= _exitFullscreen());
  }

  Future<void> restoreFullscreenOrientation() async {
    if (_disposed || !isFullScreen.value || _fullscreenTransition != null) {
      return;
    }
    if (_supportsOrientationFullscreen) {
      await AutoOrientation.landscapeAutoMode();
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _enterFullscreen() async {
    isFullScreen.value = true;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (_supportsOrientationFullscreen) {
        await AutoOrientation.landscapeAutoMode();
      }
    } finally {
      _fullscreenTransition = null;
    }
  }

  Future<void> _exitFullscreen() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // 退出全屏只该解除全屏时的横屏锁定，而不是把设备按回竖屏——
      // 应用本身是支持横屏的，锁回去会让横屏用户被强行转向。
      if (_supportsOrientationFullscreen) {
        await AutoOrientation.fullAutoMode();
      }
      isFullScreen.value = false;
    } finally {
      _fullscreenTransition = null;
    }
  }

  bool get _supportsOrientationFullscreen => AppPlatform.isMobile;

  Future<void> setDebugHudEnabled(bool enabled) async {
    if (_disposed ||
        debugHudUpdating.value ||
        debugHudEnabled.value == enabled) {
      return;
    }
    debugHudUpdating.value = true;
    try {
      await _player.setDebugHudEnabled(enabled);
      if (!_disposed) debugHudEnabled.value = enabled;
    } finally {
      if (!_disposed) debugHudUpdating.value = false;
    }
  }

  void _resetDanmakuSecond() => _lastDanmakuSecond = null;

  Future<void> close() async {
    if (_disposed && _closeFuture == null) return;
    final existing = _closeFuture;
    if (existing != null) {
      await existing;
      return;
    }
    final future = _closeSafely();
    _closeFuture = future;
    await future;
  }

  Future<void> _closeSafely() async {
    _disposed = true;
    try {
      await _player.setSystemMediaNavigation(
        previousEnabled: false,
        nextEnabled: false,
      );
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace: stackTrace,
        message: '关闭系统媒体控制失败',
        notify: false,
      );
    }
    try {
      await _eventSubscription?.cancel();
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace: stackTrace,
        message: '关闭 Erika 事件订阅失败',
        notify: false,
      );
    }
    try {
      await _player.dispose();
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace: stackTrace,
        message: '释放 Erika 播放器失败',
        notify: false,
      );
    }
    _danmakuController?.clear();
    _danmakuController = null;
    await _errors.close();
    await _completed.close();
  }
}
