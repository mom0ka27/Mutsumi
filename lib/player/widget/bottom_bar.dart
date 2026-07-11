import '../extension/duration.dart';
import '../controller.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

class BottomBar extends StatefulWidget {
  final IndexPlayerController controller;

  const BottomBar({super.key, required this.controller});

  @override
  State<BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<BottomBar> {
  @override
  Widget build(BuildContext context) {
    var playerState = widget.controller.state;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 15),
          child: Obx(
            () => ProgressBar(
              progress: widget.controller.sliderPostion.value,
              total: playerState.duration,
              buffered: playerState.buffer,
              baseBarColor: Colors.white.withValues(alpha: 0.2),
              bufferedBarColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.4),
              timeLabelLocation: TimeLabelLocation.none,
              barHeight: 4.0,
              thumbRadius: 6.0,
              onDragStart: (d) {
                widget.controller.wantSeeking.value = true;
              },
              onDragUpdate: (d) {
                widget.controller.sliderPostion.value = d.timeStamp;
              },
              onSeek: (d) {
                widget.controller.seek(d);
              },
            ),
          ),
        ),
        Row(
          children: [
            StreamBuilder(
              stream: widget.controller.stream.playing,
              builder: (c, v) => widget.controller.seeking
                  ? Padding(
                      padding: EdgeInsets.symmetric(horizontal: 15),
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
                    )
                  : IconButton(
                      onPressed: () {
                        if (widget.controller.state.playing) {
                          widget.controller.pause();
                        } else {
                          widget.controller.play();
                        }
                      },
                      icon: Icon(
                        v.data == false ? Icons.play_arrow : Icons.pause,
                        color: Colors.white,
                      ),
                    ),
            ),
            widget.controller.isFullScreen.value
                ? IconButton(
                    icon: Icon(Icons.skip_next, color: Colors.white),
                    onPressed: () {},
                  )
                : SizedBox(),
            SizedBox(width: 10),
            Obx(
              () => Text(
                "${widget.controller.sliderPostion.value.str} / ${playerState.duration.str}",
                style: TextStyle(color: Colors.white),
              ),
            ),
            Spacer(),
            Obx(
              () => Material(
                color: Colors.transparent,
                child: Switch(
                  value: widget.controller.enableDanmaku.value,
                  onChanged: (v) {
                    widget.controller.enableDanmaku.value = v;
                  },
                ),
              ),
            ),
            SizedBox(width: 10),
            IconButton(
              icon: Obx(
                () => Icon(
                  widget.controller.isFullScreen.value
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  color: Colors.white,
                ),
              ),
              onPressed: () async {
                if (widget.controller.isFullScreen.value) {
                  widget.controller.exitFullscreen();
                } else {
                  widget.controller.enterFullscreen();
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
