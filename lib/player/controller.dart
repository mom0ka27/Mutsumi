import 'dart:async';
import 'dart:io';

import 'model/danmaku.dart';
import 'model/option.dart';
import 'model/video.dart' as models;

import 'package:auto_orientation_v2/auto_orientation_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ns_danmaku/ns_danmaku.dart';
import 'package:path_provider/path_provider.dart';

class IndexPlayerController {
  final _player = Player(
    configuration: PlayerConfiguration(libass: true),
  ); //configuration: PlayerConfiguration(vo: "gpu")
  late final VideoController _controller = VideoController(
    _player,
    configuration: const VideoControllerConfiguration(
      // hwdec: "mediacodec",
      // vo: "gpu",
    ),
  );

  final IndexPlayerOptions options;

  final GlobalKey<VideoState> _videoKey = GlobalKey();

  DanmakuController? _danmakuController;
  final Rx<bool> enableDanmaku = true.obs;
  DanmakuList? _danmakuList;

  VideoController get videoController => _controller;

  PlayerState get state => _player.state;

  bool _seeking = false;

  /// 是否在加载快进
  bool get seeking => _seeking;

  /// 显示快进条
  final Rx<bool> wantSeeking = false.obs;

  /// 进度条位置
  final Rx<Duration> sliderPostion = Rx(Duration.zero);

  final Rx<bool> isFullScreen = false.obs;

  final Rx<models.Video?> _video = Rx(null);

  Rx<models.Video?> get video => _video;

  GlobalKey<VideoState> get videoKey => _videoKey;

  bool _disposed = false;
  Future<void>? _fullscreenTransition;

  bool get disposed => _disposed;
  StreamSubscription<Duration>? _positionSubscription;
  double _currentRate = 1.0;
  int? _lastDanmakuSecond;
  Future<Directory>? _subtitleFontDirectory;
  var _videoGeneration = 0;

  IndexPlayerController({this.options = const IndexPlayerOptions()}) {
    // (_player.platform as NativePlayer)
    //     .getProperty("gpu-api")
    //     .then((v) => print("gpu-api: $v"));

    _positionSubscription = stream.position.listen((position) {
      if (!_disposed && !seeking && wantSeeking.isFalse) {
        sliderPostion.value = position;
      }
      final danmakuController = _danmakuController;
      final second = position.inSeconds;
      if (_disposed ||
          !enableDanmaku.value ||
          danmakuController == null ||
          _lastDanmakuSecond == second) {
        return;
      }
      _lastDanmakuSecond = second;
      danmakuController.addItems(_danmakuList?.getDanmakus(second) ?? []);
    });
  }

  /// 设置播放的视频
  ///
  /// 视频加载后立即返回，不会等待弹幕加载
  Future<void> setVideo(models.Video video, {Duration? start}) async {
    if (_disposed) {
      return;
    }

    this.video.value = video;
    final videoGeneration = ++_videoGeneration;
    _lastDanmakuSecond = null;
    _danmakuList = null;
    final fontDirectory = await (_subtitleFontDirectory ??=
        _prepareSubtitleFont());
    await _setNativeProperty('sub-font-provider', 'auto');
    await _setNativeProperty('sub-fonts-dir', fontDirectory.path);
    await _setNativeProperty('sub-font', 'Resource Han Rounded CN');

    if (video is models.NetworkVideo) {
      await _setNativeProperty('cache', 'yes');
      await _setNativeProperty('demuxer-readahead-secs', '30');
      await _setNativeProperty('demuxer-max-bytes', '128MiB');
    }
    if (_disposed) {
      return;
    }
    await _player.open(
      Media(
        video.uri.toString(),
        httpHeaders: video is models.NetworkVideo ? video.httpHeaders : null,
        start: start,
      ),
    );
    try {
      if (_disposed) {
        return;
      }
      await _player.stream.duration.first; // 等待视频加载
    } catch (_) {
      return;
    }
    if (_disposed) {
      return;
    }
    if (video.subtitleUri != null) {
      await _player.setSubtitleTrack(SubtitleTrack.uri(video.subtitleUri!));
    } else {
      await _selectSimplifiedChineseSubtitle();
    }
    _danmakuController?.clear();
    video.danmakuProvider?.getDanmakuList().then((l) {
      if (!_disposed && videoGeneration == _videoGeneration) {
        _danmakuList = l;
      }
    });
  }

  void setDanmakuController(DanmakuController controller) {
    if (_disposed) {
      return;
    }
    _danmakuController = controller;
    _lastDanmakuSecond = null;
  }

  void clearDanmakuController(DanmakuController controller) {
    if (identical(_danmakuController, controller)) {
      _danmakuController = null;
      _lastDanmakuSecond = null;
    }
  }

  void toggleDanmaku() {
    enableDanmaku.toggle();
    _lastDanmakuSecond = null;
    if (!enableDanmaku.value) {
      _danmakuController?.clear();
    }
  }

  Future<void> pause() async {
    if (_disposed) {
      return;
    }
    await _player.pause();
    _danmakuController?.pause();
  }

  Future<void> play() async {
    if (_disposed) {
      return;
    }
    await _player.play();
    _danmakuController?.resume();
  }

  Future<void> seek(Duration d) async {
    if (_disposed) {
      return;
    }

    wantSeeking.value = false;

    _seeking = true;
    sliderPostion.value = d;
    _lastDanmakuSecond = null;

    _player.pause();
    _danmakuController?.pause();

    if (_disposed) {
      _seeking = false;
      return;
    }
    await _player.seek(d);

    if (_disposed) {
      _seeking = false;
      return;
    }
    _danmakuController?.clear();
    await _player.play();
    _danmakuController?.resume();
    _seeking = false;
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
    await AutoOrientation.landscapeAutoMode();
    if (!_disposed) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _enterFullscreen() async {
    isFullScreen.value = true;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!_disposed) {
        await AutoOrientation.landscapeAutoMode();
      }
    } finally {
      _fullscreenTransition = null;
    }
  }

  Future<void> _exitFullscreen() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      );
      if (!_disposed) {
        await AutoOrientation.portraitAutoMode();
      }
      if (!_disposed) {
        isFullScreen.value = false;
      }
    } finally {
      _fullscreenTransition = null;
    }
  }

  Future<void> setSpeed(double rate) async {
    if (_disposed || _currentRate == rate) {
      return;
    }

    final currentRate = _currentRate;
    _currentRate = rate;
    _danmakuController?.updateOption(
      _danmakuController!.option.copyWith(
        duration: _danmakuController!.option.duration * currentRate / rate,
      ),
    );
    if (_disposed) {
      return;
    }
    await _player.setRate(rate);
  }

  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    if (_disposed || state.track.subtitle == track) {
      return;
    }
    await _player.setSubtitleTrack(track);
  }

  Future<void> _selectSimplifiedChineseSubtitle() async {
    Tracks tracks = state.tracks;
    try {
      tracks = await stream.tracks
          .firstWhere((value) => value.subtitle.any(_isSubtitleTrack))
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      tracks = state.tracks;
    }
    if (_disposed) {
      return;
    }
    final candidates = tracks.subtitle.where(_isSubtitleTrack).toList();
    if (candidates.isEmpty) {
      return;
    }
    candidates.sort(
      (left, right) => _simplifiedChineseScore(
        right,
      ).compareTo(_simplifiedChineseScore(left)),
    );
    if (_simplifiedChineseScore(candidates.first) > 0) {
      await setSubtitleTrack(candidates.first);
    }
  }

  bool _isSubtitleTrack(SubtitleTrack track) =>
      track.id != 'auto' && track.id != 'no';

  int _simplifiedChineseScore(SubtitleTrack track) {
    final value = [track.title, track.language, track.id]
        .whereType<String>()
        .join(' ')
        .toLowerCase()
        .replaceAll(RegExp(r'[-_ ]'), '');
    if (value.contains('简体') || value.contains('简中')) {
      return 100;
    }
    if (value.contains('simplified') ||
        value.contains('zhhans') ||
        value.contains('zhcn') ||
        value.contains('zhochs') ||
        value.contains('chichs')) {
      return 90;
    }
    if ((value.contains('chs') || value.contains('sc')) &&
        !value.contains('cht')) {
      return 80;
    }
    if (value == 'zh' || value == 'zho' || value == 'chi') {
      return 50;
    }
    return 0;
  }

  Future<void> _setNativeProperty(String name, String value) async {
    try {
      if (_disposed) {
        return;
      }
      await (_player.platform as dynamic).setProperty(name, value);
    } catch (_) {}
  }

  Future<Directory> _prepareSubtitleFont() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final fontDirectory = Directory('${supportDirectory.path}/subtitle_fonts');
    final fontFile = File(
      '${fontDirectory.path}/ResourceHanRoundedCN-Regular.ttf',
    );
    if (!await fontFile.exists()) {
      await fontDirectory.create(recursive: true);
      final data = await rootBundle.load(
        'assets/fonts/ResourceHanRoundedCN-Regular.ttf',
      );
      await fontFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return fontDirectory;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _player.dispose();
    _danmakuController?.clear();
    _danmakuController = null;
    _danmakuList = null;
    _lastDanmakuSecond = null;
  }

  PlayerStream get stream => _player.stream;
}
