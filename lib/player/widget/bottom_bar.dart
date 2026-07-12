import '../extension/duration.dart';
import '../controller.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:media_kit/media_kit.dart';

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
    final accentColor = Theme.of(context).colorScheme.primaryFixed;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 32, 8, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.82)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Obx(
              () => ProgressBar(
                progress: widget.controller.sliderPostion.value,
                total: playerState.duration,
                buffered: playerState.buffer,
                baseBarColor: Colors.white.withValues(alpha: 0.2),
                bufferedBarColor: Colors.white.withValues(alpha: 0.35),
                progressBarColor: accentColor,
                thumbColor: accentColor,
                timeLabelLocation: TimeLabelLocation.none,
                barHeight: 3.0,
                thumbRadius: 6.5,
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
              const SizedBox(width: 10),
              Obx(
                () => Text(
                  "${widget.controller.sliderPostion.value.str} / ${playerState.duration.str}",
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Spacer(),
              Obx(
                () => Semantics(
                  label: '弹幕',
                  button: true,
                  selected: widget.controller.enableDanmaku.value,
                  child: InkWell(
                    onTap: widget.controller.toggleDanmaku,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: widget.controller.enableDanmaku.value
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        '弹',
                        style: TextStyle(
                          color: widget.controller.enableDanmaku.value
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              StreamBuilder<Tracks>(
                stream: widget.controller.stream.tracks,
                initialData: widget.controller.state.tracks,
                builder: (context, tracksSnapshot) => StreamBuilder<Track>(
                  stream: widget.controller.stream.track,
                  initialData: widget.controller.state.track,
                  builder: (context, trackSnapshot) {
                    final tracks = (tracksSnapshot.data?.subtitle ?? const [])
                        .where((track) => track.id != 'auto')
                        .toList();
                    final selected = trackSnapshot.data?.subtitle;
                    return PopupMenuButton<SubtitleTrack>(
                      tooltip: '选择字幕',
                      enabled: tracks.isNotEmpty,
                      color: Colors.black.withValues(alpha: 0.9),
                      position: PopupMenuPosition.over,
                      onSelected: widget.controller.setSubtitleTrack,
                      itemBuilder: (context) => tracks
                          .map(
                            (track) => PopupMenuItem(
                              value: track,
                              child: Row(
                                children: [
                                  Icon(
                                    selected == track
                                        ? Icons.check_rounded
                                        : Icons.closed_caption_outlined,
                                    color: selected == track
                                        ? accentColor
                                        : Colors.white70,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      _subtitleLabel(track),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      icon: Icon(
                        selected?.id == 'no'
                            ? Icons.closed_caption_disabled_outlined
                            : Icons.closed_caption_rounded,
                        color: selected?.id == 'no'
                            ? Colors.white70
                            : Colors.white,
                      ),
                    );
                  },
                ),
              ),
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
      ),
    );
  }

  String _subtitleLabel(SubtitleTrack track) {
    if (track.id == 'no') {
      return '关闭字幕';
    }
    final title = track.title?.trim();
    final language = track.language?.trim();
    if (title != null && title.isNotEmpty) {
      return language != null && language.isNotEmpty
          ? '$title · $language'
          : title;
    }
    if (language != null && language.isNotEmpty) {
      return language;
    }
    return '字幕 ${track.id}';
  }
}
