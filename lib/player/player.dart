import 'dart:async';
import 'dart:ui';

import 'package:mutsumi/constants.dart';

import 'extension/duration.dart';
import 'widget/top_bar.dart';
import 'controller.dart';
import 'widget/bottom_bar.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/extensions/duration.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ns_danmaku/ns_danmaku.dart';

class IndexPlayer extends StatefulWidget {
  final IndexPlayerController controller;

  const IndexPlayer(this.controller, {super.key});

  @override
  State<IndexPlayer> createState() => _IndexPlayerState();

  static void init() {
    MediaKit.ensureInitialized();
  }
}

class _IndexPlayerState extends State<IndexPlayer> {
  Rx<bool> showControls = false.obs;
  Rx<bool> superSpeed = false.obs;

  Timer? _autoHideControls;
  Timer? _superSpeedTimer;
  StreamSubscription<bool>? _showControlsSubscription;
  bool _superSpeedActive = false;

  @override
  void initState() {
    super.initState();
    // 自动隐藏控制栏
    _showControlsSubscription = showControls.listen((v) {
      _autoHideControls?.cancel();
      if (v) {
        _autoHideControls = Timer(const Duration(seconds: 5), () {
          showControls.value = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _autoHideControls?.cancel();
    _superSpeedTimer?.cancel();
    _showControlsSubscription?.cancel();
    super.dispose();
  }

  void _scheduleSuperSpeed() {
    _superSpeedTimer?.cancel();
    _superSpeedTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted || widget.controller.disposed) {
        return;
      }
      _superSpeedActive = true;
      superSpeed.value = true;
      widget.controller.setSpeed(2);
      HapticFeedback.mediumImpact();
    });
  }

  void _cancelSuperSpeed() {
    _superSpeedTimer?.cancel();
    _superSpeedTimer = null;
    if (!_superSpeedActive) {
      return;
    }

    _superSpeedActive = false;
    superSpeed.value = false;
    widget.controller.setSpeed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => SizedBox(
        height: widget.controller.isFullScreen.value
            ? MediaQuery.of(context).size.height
            : MediaQuery.of(context).size.width / 16 * 9,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Video(
              key: widget.controller.videoKey,
              controller: widget.controller.videoController,
              controls: null,
              subtitleViewConfiguration: SubtitleViewConfiguration(
                style: TextStyle(
                  color: Colors.white,
                  // fontFamily: "FangZhengZhunYuanJianTi",
                  // borderColor: Colors.pink[200],
                  fontSize: widget.controller.isFullScreen.value ? 28 : 20,
                  fontWeight: FontWeight.w600,
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 4),
                    Shadow(color: Colors.black, offset: Offset(1, 1)),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  widget.controller.isFullScreen.value ? 24 : 12,
                ),
                // letterSpacing: 0.0,
                // wordSpacing: 0.0,
              ),
            ),
            Opacity(
              opacity: widget.controller.enableDanmaku.value ? 1 : 0,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 25),
                child: DanmakuView(
                  createdController: (c) {
                    widget.controller.setDanmakuController(c);
                  },
                  option: DanmakuOption(strokeWidth: 1, duration: 6),
                ),
              ),
            ),
            Listener(
              onPointerDown: (_) => _scheduleSuperSpeed(),
              onPointerUp: (_) => _cancelSuperSpeed(),
              onPointerCancel: (_) => _cancelSuperSpeed(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 显示控制栏
                onTap: () {
                  showControls.value = !showControls.value;
                },
                // 暂停/继续
                onDoubleTap: () {
                  if (widget.controller.state.playing) {
                    widget.controller.pause();
                  } else {
                    widget.controller.play();
                  }
                },
                // 快进
                onHorizontalDragStart: (ignore) {
                  _cancelSuperSpeed();
                  widget.controller.wantSeeking.value = true;
                },
                onHorizontalDragUpdate: (details) {
                  final int curSliderPosition =
                      widget.controller.sliderPostion.value.inMilliseconds;
                  final double scale = 90000 / MediaQuery.sizeOf(context).width;
                  final Duration pos = Duration(
                    milliseconds:
                        curSliderPosition + (details.delta.dx * scale).round(),
                  );

                  widget.controller.sliderPostion.value = pos.clamp(
                    Duration.zero,
                    widget.controller.state.duration,
                  );
                },
                onHorizontalDragEnd: (DragEndDetails details) {
                  widget.controller.seek(widget.controller.sliderPostion.value);
                },
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Obx(
                () => Padding(
                  padding: widget.controller.isFullScreen.value
                      ? EdgeInsets.symmetric(horizontal: 40)
                      : EdgeInsets.zero,
                  child: AnimatedOpacity(
                    opacity: showControls.value ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: IgnorePointer(
                      ignoring: showControls.isFalse,
                      child: BottomBar(controller: widget.controller),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: AnimatedOpacity(
                opacity: showControls.value ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: showControls.isFalse,
                  child: StreamBuilder<bool>(
                    stream: widget.controller.stream.playing,
                    builder: (context, snapshot) => IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.48),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(64, 64),
                        iconSize: 34,
                      ),
                      onPressed: () {
                        if (widget.controller.state.playing) {
                          widget.controller.pause();
                        } else {
                          widget.controller.play();
                        }
                      },
                      icon: Icon(
                        snapshot.data == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Obx(
                () => Padding(
                  padding: widget.controller.isFullScreen.value
                      ? EdgeInsets.symmetric(horizontal: 40)
                      : EdgeInsets.zero,
                  child: AnimatedOpacity(
                    opacity: showControls.value ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: IgnorePointer(
                      ignoring: showControls.isFalse,
                      child: TopBar(controller: widget.controller),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment(0, -0.8),
              child: Obx(
                () => AnimatedOpacity(
                  opacity: superSpeed.value ? 1 : 0,
                  duration: const Duration(milliseconds: 75),
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Constants.radius),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.42),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fast_forward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              SizedBox(width: 6),
                              Text(
                                "2.0× 倍速播放",
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment(0, -0.8),
              child: Obx(
                () => AnimatedOpacity(
                  opacity: widget.controller.wantSeeking.value ? 1 : 0,
                  duration: const Duration(milliseconds: 75),
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Constants.radius),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.42),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Text(
                            "${widget.controller.state.position.str}  →  ${widget.controller.sliderPostion.value.str}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
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
}
