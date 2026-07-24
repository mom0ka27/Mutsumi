import 'dart:async';
import 'dart:io';

import 'package:auto_orientation_v2/auto_orientation_v2.dart';
import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:ns_danmaku/ns_danmaku.dart';
import 'package:path_provider/path_provider.dart';

import 'model/danmaku.dart';
import 'model/option.dart';
import 'model/video.dart' as models;

class PlayerState {
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration buffer = Duration.zero;
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
  final _player = ErikaPlayer(outputMode: ErikaOutputMode.appleEdr);
  final IndexPlayerOptions options;
  final _state = PlayerState();
  final _revision = 0.obs;
  final _playing = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _events = StreamController<ErikaPlayerEvent>.broadcast();
  final GlobalKey _videoKey = GlobalKey();

  DanmakuController? _danmakuController;
  final Rx<bool> enableDanmaku = true.obs;
  DanmakuList? _danmakuList;
  final danmakuCount = (-1).obs;
  final danmakuEpisodeId = RxnInt();
  final Rx<bool> wantSeeking = false.obs;
  final Rx<Duration> sliderPostion = Rx(Duration.zero);
  final Rx<bool> isFullScreen = false.obs;
  final Rx<models.Video?> _video = Rx(null);

  StreamSubscription<ErikaPlayerEvent>? _eventSubscription;
  Future<void>? _fullscreenTransition;
  bool _disposed = false;
  bool _seeking = false;
  int? _lastDanmakuSecond;
  int _videoGeneration = 0;
  double _currentRate = 1.0;

  IndexPlayerController({this.options = const IndexPlayerOptions()}) {
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
  int get revision => _revision.value;

  void _handleEvent(ErikaPlayerEvent event) {
    if (_disposed) return;
    _state.position = event.position;
    _state.duration = event.duration;
    _state.playing = event.state == ErikaPlaybackState.playing;
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
    if (!_seeking) sliderPostion.value = event.position;
    _pushDanmaku(event.position);
  }

  void _updateTracks(List<ErikaTrackInfo> tracks, int? selectedId) {
    final subtitles = tracks
        .where((track) => track.kind == ErikaTrackKind.subtitle)
        .map(
          (track) => PlayerSubtitleTrack(
            id: track.id,
            title: track.title,
            language: track.language,
            disabled: !track.selected && selectedId == null,
          ),
        )
        .toList(growable: false);
    _state.subtitles = subtitles;
    _state.subtitle = subtitles.cast<PlayerSubtitleTrack?>().firstWhere(
      (track) => track?.id == selectedId,
      orElse: () => null,
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

  Future<void> setVideo(models.Video video, {Duration? start}) async {
    if (_disposed) return;
    this.video.value = video;
    final generation = ++_videoGeneration;
    _resetDanmakuSecond();
    _danmakuList = null;
    danmakuCount.value = -1;
    danmakuEpisodeId.value = null;
    await _player.open(
      video.uri.toString(),
      httpHeaders: video is models.NetworkVideo ? video.httpHeaders : null,
    );
    if (start != null && start > Duration.zero) await _player.seek(start);
    if (video.subtitleUri != null) {
      await _player.addExternalSubtitle(video.subtitleUri!);
    }
    final provider = video.danmakuProvider;
    if (provider != null) {
      provider.getDanmakuList().then((result) {
        if (!_disposed && generation == _videoGeneration) {
          _danmakuList = result.list;
          danmakuCount.value = result.count;
          danmakuEpisodeId.value = result.episodeId;
        }
      });
    }
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
    _danmakuController?.clear();
    final result = await provider.getDanmakuList();
    if (!_disposed) {
      _danmakuList = result.list;
      danmakuCount.value = result.count;
      danmakuEpisodeId.value = result.episodeId;
      _resetDanmakuSecond();
    }
  }

  Future<void> play() async {
    if (_disposed) return;
    await _player.play();
    _danmakuController?.resume();
  }

  Future<void> pause() async {
    if (_disposed) return;
    await _player.pause();
    _danmakuController?.pause();
  }

  Future<void> togglePlayback() => _state.playing ? pause() : play();

  void beginSeeking() {
    if (!_disposed) {
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
    _seeking = false;
    _resetDanmakuSecond();
  }

  Future<void> setSpeed(double rate) async {
    if (_disposed || _currentRate == rate) return;
    _currentRate = rate;
    await _player.setPlaybackRate(rate);
  }

  Future<void> setSubtitleTrack(PlayerSubtitleTrack track) async {
    if (!_disposed) {
      await _player.selectSubtitleTrack(track.disabled ? null : track.id);
    }
  }

  Future<void> loadExternalSubtitleTracks(List<SubtitleTrack> tracks) async {
    for (final track in tracks) {
      if (_disposed) {
        return;
      }
      await _player.addExternalSubtitle(track.path!);
    }
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
    if (!Platform.isMacOS) await AutoOrientation.landscapeAutoMode();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _enterFullscreen() async {
    isFullScreen.value = true;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!Platform.isMacOS) await AutoOrientation.landscapeAutoMode();
    } finally {
      _fullscreenTransition = null;
    }
  }

  Future<void> _exitFullscreen() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (!Platform.isMacOS) await AutoOrientation.portraitAutoMode();
      isFullScreen.value = false;
    } finally {
      _fullscreenTransition = null;
    }
  }

  Future<PlayerInfo> getPlayerInfo() async {
    final event = await eventStream.firstWhere(
      (event) => event.video.width > 0,
    );
    return PlayerInfo(
      videoCodec: event.decoder?.codec ?? '-',
      width: event.video.width,
      height: event.video.height,
      pixelFormat: event.decoder?.pixelFormat ?? '-',
      hwDecoder: event.decoder?.activeBackend ?? '-',
    );
  }

  void _resetDanmakuSecond() => _lastDanmakuSecond = null;

  Future<Directory> prepareSubtitleFont() async =>
      getApplicationSupportDirectory();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSubscription?.cancel();
    await _player.dispose();
    await _playing.close();
    await _errors.close();
    await _events.close();
    _danmakuController?.clear();
    _danmakuController = null;
  }
}

class PlayerInfo {
  const PlayerInfo({
    required this.videoCodec,
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.hwDecoder,
  });

  final String videoCodec;
  final int width;
  final int height;
  final String pixelFormat;
  final String hwDecoder;

  String get resolution => width > 0 && height > 0 ? '${width}x$height' : '-';
  String get videoBitrate => '-';
  String get audioCodec => '-';
  String get audioBitrate => '-';
  String get frameRate => '-';
  String get demuxer => 'Erika';
  String get videoFormat => 'Erika';
}

class SubtitleTrack {
  const SubtitleTrack({required this.path});

  final String? path;
}
