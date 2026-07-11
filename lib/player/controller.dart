import 'dart:async';

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

  bool get disposed => _disposed;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _danmakuSubscription;
  double _currentRate = 1.0;
  int _lastDanmakuSecond = -1;

  IndexPlayerController({this.options = const IndexPlayerOptions()}) {
    // (_player.platform as NativePlayer)
    //     .getProperty("gpu-api")
    //     .then((v) => print("gpu-api: $v"));

    _positionSubscription = stream.position.listen((position) {
      if (!_disposed && !seeking && wantSeeking.isFalse) {
        sliderPostion.value = position;
      }
    });

    _danmakuSubscription = stream.position.listen((position) {
      if (_disposed || position.inSeconds == _lastDanmakuSecond) {
        return;
      }
      _lastDanmakuSecond = position.inSeconds;
      _danmakuController?.addItems(
        _danmakuList?.getDanmakus(position.inSeconds) ?? [],
      );
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
    _lastDanmakuSecond = -1;
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
    }
    _danmakuController?.clear();
    video.danmakuProvider?.getDanmakuList().then((l) {
      if (!_disposed) {
        _danmakuList = l;
      }
    });
  }

  void setDanmakuController(DanmakuController controller) {
    if (_disposed) {
      return;
    }
    _danmakuController = controller;
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
    if (_disposed) {
      return;
    }
    await AutoOrientation.landscapeAutoMode();
    if (_disposed) {
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    isFullScreen.value = true;
  }

  Future<void> exitFullscreen() async {
    if (_disposed) {
      return;
    }
    await AutoOrientation.portraitAutoMode();
    if (_disposed) {
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    isFullScreen.value = false;
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

  Future<void> _setNativeProperty(String name, String value) async {
    try {
      if (_disposed) {
        return;
      }
      await (_player.platform as dynamic).setProperty(name, value);
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _positionSubscription?.cancel();
    await _danmakuSubscription?.cancel();
    await _player.dispose();
    _danmakuController?.clear();
  }

  PlayerStream get stream => _player.stream;
}
