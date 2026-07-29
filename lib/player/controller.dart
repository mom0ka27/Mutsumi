import 'dart:async';

import 'package:auto_orientation_v2/auto_orientation_v2.dart';
import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:ns_danmaku/ns_danmaku.dart';

import '../core/platform/app_platform.dart';
import 'model/danmaku.dart';
import 'model/option.dart';
import 'model/playlist.dart';
import 'model/video.dart' as models;

class PlayerState {
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool buffering = false;
  bool playing = false;
  List<PlayerSubtitleTrack> subtitles = const [];
  PlayerSubtitleTrack? subtitle;
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
  final _player = ErikaPlayer();
  final IndexPlayerOptions options;
  final PlayerPlaylist playlist;
  final Future<void> Function(PlayerPlaybackSnapshot snapshot)? onItemLeaving;
  final _state = PlayerState();
  final _revision = 0.obs;
  final _playing = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _events = StreamController<ErikaPlayerEvent>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final GlobalKey _videoKey = GlobalKey();

  DanmakuController? _danmakuController;
  final Rx<bool> enableDanmaku = true.obs;
  DanmakuList? _danmakuList;
  final danmakuCount = (-1).obs;
  final danmakuEpisodeId = RxnInt();
  final Rx<bool> wantSeeking = false.obs;
  final Rx<Duration> sliderPostion = Rx(Duration.zero);
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
  bool _seeking = false;
  int? _lastDanmakuSecond;
  int _videoGeneration = 0;
  bool _playbackCompleted = false;
  bool _resumeAfterSeek = false;
  Completer<Duration>? _durationCompleter;

  IndexPlayerController({
    required this.playlist,
    this.options = const IndexPlayerOptions(),
    this.onItemLeaving,
  }) {
    _eventSubscription = _player.events.listen(_handleEvent);
  }

  PlayerState get state => _state;
  ErikaPlayer get player => _player;
  GlobalKey get videoKey => _videoKey;
  Rx<models.Video?> get video => _video;
  bool get disposed => _disposed;
  bool get seeking => _seeking;
  Stream<bool> get playingStream => _playing.stream;
  Stream<String> get errorStream => _errors.stream;
  Stream<ErikaPlayerEvent> get eventStream => _events.stream;
  Stream<void> get completedStream => _completed.stream;
  int get revision => _revision.value;
  bool get hasNext =>
      selectedIndex.value != null &&
      selectedIndex.value! < playlist.items.length - 1;
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

  void _handleEvent(ErikaPlayerEvent event) {
    if (_disposed) return;
    if (event.kind == ErikaEventKind.positionChanged) {
      _state.position = event.position;
      if (!_seeking) sliderPostion.value = event.position;
    }
    if (event.kind == ErikaEventKind.durationChanged) {
      _state.duration = event.duration;
      final completer = _durationCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(event.duration);
      }
    }
    _state.buffering = event.buffering;
    if (event.state == ErikaPlaybackState.playing) {
      _state.playing = true;
    } else if (event.state == ErikaPlaybackState.paused ||
        event.state == ErikaPlaybackState.stopped) {
      _state.playing = false;
    }
    if (event.kind == ErikaEventKind.tracksChanged ||
        event.kind == ErikaEventKind.trackSelectionChanged) {
      _updateTracks(event.trackList, event.trackSelection.subtitle);
    }
    _revision.value++;
    _playing.add(_state.playing);
    _events.add(event);
    if (event.error != null && event.error!.isNotEmpty) {
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
    _state.subtitles = subtitles;
    _state.subtitle = subtitles.firstWhere(
      (track) => track.id == (selectedId ?? -1),
      orElse: () => subtitles.first,
    );
  }

  void _pushDanmaku(Duration position) {
    final second = position.inSeconds;
    if (!enableDanmaku.value ||
        _danmakuController == null ||
        _lastDanmakuSecond == second) {
      return;
    }
    _lastDanmakuSecond = second;
    _danmakuController!.addItems(_danmakuList?.getDanmakus(second) ?? []);
  }

  Future<void> selectIndex(int index) async {
    if (_disposed || index < 0 || index >= playlist.items.length) return;
    if (index == selectedIndex.value || index == loadingIndex.value) return;
    final generation = ++_videoGeneration;
    final snapshot = currentSnapshot;
    loadingIndex.value = index;
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
    } catch (error) {
      if (!_disposed && generation == _videoGeneration) {
        _errors.add(error.toString());
      }
    } finally {
      if (!_disposed && generation == _videoGeneration) {
        loadingIndex.value = null;
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
      unawaited(
        provider.getDanmakuList().then((result) {
          if (!_disposed && generation == _videoGeneration) {
            _danmakuList = result.list;
            danmakuCount.value = result.count;
            danmakuEpisodeId.value = result.episodeId;
          }
        }),
      );
    }
  }

  void _resetPlaybackState() {
    _state.position = Duration.zero;
    _state.duration = Duration.zero;
    _state.buffering = false;
    _state.playing = false;
    _state.subtitles = const [];
    _state.subtitle = null;
    sliderPostion.value = Duration.zero;
    _revision.value++;
  }

  void setDanmakuController(DanmakuController controller) {
    if (!_disposed) _danmakuController = controller;
  }

  void clearDanmakuController(DanmakuController controller) {
    if (identical(_danmakuController, controller)) _danmakuController = null;
  }

  void toggleDanmaku() {
    enableDanmaku.toggle();
    _resetDanmakuSecond();
    if (!enableDanmaku.value) _danmakuController?.clear();
  }

  Future<void> refreshDanmaku() async {
    final provider = _video.value?.danmakuProvider;
    if (_disposed || provider == null) return;
    final generation = _videoGeneration;
    _danmakuController?.clear();
    final result = await provider.getDanmakuList();
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
    await _player.pause();
    _danmakuController?.pause();
  }

  Future<void> togglePlayback() => _state.playing ? pause() : play();

  void beginSeeking() {
    if (!_disposed) {
      _resumeAfterSeek = _state.playing;
      _seeking = true;
      wantSeeking.value = true;
    }
  }

  void updateSeekingPosition(Duration position) {
    if (_disposed) return;
    sliderPostion.value = position < Duration.zero
        ? Duration.zero
        : position > _state.duration
        ? _state.duration
        : position;
  }

  Future<void> endSeeking([Duration? position]) async {
    if (position != null) updateSeekingPosition(position);
    await seek(sliderPostion.value);
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    _seeking = true;
    wantSeeking.value = false;
    await _player.seek(position < Duration.zero ? Duration.zero : position);
    if (_resumeAfterSeek) await _player.play();
    _resumeAfterSeek = false;
    _seeking = false;
    _resetDanmakuSecond();
  }

  Future<void> seekBy(Duration offset) async {
    if (_disposed) return;
    final target = _state.position + offset;
    final position = target < Duration.zero
        ? Duration.zero
        : target > _state.duration
        ? _state.duration
        : target;
    await _player.seek(position);
    _resetDanmakuSecond();
  }

  Future<void> adjustVolume(double delta) async {
    if (_disposed) return;
    final previous = volume.value;
    final value = (volume.value + delta).clamp(0.0, 1.0).toDouble();
    if (value == previous) return;
    volume.value = value;
    try {
      await _player.setVolume(value);
    } catch (_) {
      if (!_disposed && volume.value == value) volume.value = previous;
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

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSubscription?.cancel();
    await _player.dispose();
    await _playing.close();
    await _errors.close();
    await _events.close();
    await _completed.close();
    _danmakuController?.clear();
    _danmakuController = null;
  }
}
