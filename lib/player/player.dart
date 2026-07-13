import 'dart:ui';

import 'package:mutsumi/constants.dart';

import 'extension/duration.dart';
import 'widget/top_bar.dart';
import 'controller.dart';
import 'player_interaction_state.dart';
import 'widget/bottom_bar.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
  late final PlayerInteractionState _interaction;
  DanmakuController? _danmakuController;

  @override
  void initState() {
    super.initState();
    _interaction = PlayerInteractionState(widget.controller);
  }

  @override
  void dispose() {
    _interaction.dispose();
    final danmakuController = _danmakuController;
    if (danmakuController != null) {
      widget.controller.clearDanmakuController(danmakuController);
    }
    super.dispose();
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
                    _danmakuController = c;
                    widget.controller.setDanmakuController(c);
                  },
                  option: DanmakuOption(strokeWidth: 1, duration: 6),
                ),
              ),
            ),
            Listener(
              onPointerDown: (_) => _interaction.scheduleSuperSpeed(),
              onPointerUp: (_) => _interaction.cancelSuperSpeed(),
              onPointerCancel: (_) => _interaction.cancelSuperSpeed(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _interaction.toggleControls,
                onDoubleTap: widget.controller.togglePlayback,
                onHorizontalDragStart: (ignore) {
                  _interaction.cancelSuperSpeed();
                  widget.controller.beginSeeking();
                },
                onHorizontalDragUpdate: (details) {
                  final int curSliderPosition =
                      widget.controller.sliderPostion.value.inMilliseconds;
                  final double scale = 90000 / MediaQuery.sizeOf(context).width;
                  final Duration pos = Duration(
                    milliseconds:
                        curSliderPosition + (details.delta.dx * scale).round(),
                  );

                  widget.controller.updateSeekingPosition(pos);
                },
                onHorizontalDragEnd: (DragEndDetails details) {
                  widget.controller.endSeeking();
                },
              ),
            ),
            _PlayerControlsOverlay(
              alignment: Alignment.bottomCenter,
              controller: widget.controller,
              visible: _interaction.showControls,
              child: BottomBar(controller: widget.controller),
            ),
            _PlayerControlsOverlay(
              alignment: Alignment.topCenter,
              controller: widget.controller,
              visible: _interaction.showControls,
              child: TopBar(controller: widget.controller),
            ),
            _PlayerStatusOverlay(
              alignment: Alignment(0, -0.8),
              visible: _interaction.superSpeed,
              childBuilder: () => const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fast_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  SizedBox(width: 6),
                  Text('2.0× 倍速播放', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            _PlayerStatusOverlay(
              alignment: Alignment(0, -0.8),
              visible: widget.controller.wantSeeking,
              childBuilder: () => Text(
                '${widget.controller.state.position.str}  →  ${widget.controller.sliderPostion.value.str}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerControlsOverlay extends StatelessWidget {
  const _PlayerControlsOverlay({
    required this.alignment,
    required this.controller,
    required this.visible,
    required this.child,
  });

  final Alignment alignment;
  final IndexPlayerController controller;
  final RxBool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Obx(
        () => Padding(
          padding: controller.isFullScreen.value
              ? const EdgeInsets.symmetric(horizontal: 40)
              : EdgeInsets.zero,
          child: AnimatedOpacity(
            opacity: visible.value ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(ignoring: !visible.value, child: child),
          ),
        ),
      ),
    );
  }
}

class _PlayerStatusOverlay extends StatelessWidget {
  const _PlayerStatusOverlay({
    required this.alignment,
    required this.visible,
    required this.childBuilder,
  });

  final Alignment alignment;
  final Rx<bool> visible;
  final Widget Function() childBuilder;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Obx(
        () => AnimatedOpacity(
          opacity: visible.value ? 1 : 0,
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
                  child: childBuilder(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
