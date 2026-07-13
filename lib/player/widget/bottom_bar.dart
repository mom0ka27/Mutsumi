import '../extension/duration.dart';
import '../controller.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:media_kit/media_kit.dart';

class BottomBar extends StatelessWidget {
  final IndexPlayerController controller;

  const BottomBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final playerState = controller.state;
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
                progress: controller.sliderPostion.value,
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
                  controller.beginSeeking();
                },
                onDragUpdate: (d) {
                  controller.updateSeekingPosition(d.timeStamp);
                },
                onSeek: (d) {
                  controller.endSeeking(d);
                },
              ),
            ),
          ),
          Row(
            children: [
              StreamBuilder(
                stream: controller.stream.playing,
                builder: (c, v) => controller.seeking
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
                        onPressed: controller.togglePlayback,
                        icon: Icon(
                          v.data == false ? Icons.play_arrow : Icons.pause,
                          color: Colors.white,
                        ),
                      ),
              ),
              controller.isFullScreen.value
                  ? IconButton(
                      icon: Icon(Icons.skip_next, color: Colors.white),
                      onPressed: () {},
                    )
                  : SizedBox(),
              const SizedBox(width: 10),
              Obx(
                () => Text(
                  "${controller.sliderPostion.value.str} / ${playerState.duration.str}",
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
                  selected: controller.enableDanmaku.value,
                  child: InkWell(
                    onTap: controller.toggleDanmaku,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: controller.enableDanmaku.value
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        '弹',
                        style: TextStyle(
                          color: controller.enableDanmaku.value
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
                stream: controller.stream.tracks,
                initialData: controller.state.tracks,
                builder: (context, tracksSnapshot) => StreamBuilder<Track>(
                  stream: controller.stream.track,
                  initialData: controller.state.track,
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
                      onSelected: controller.setSubtitleTrack,
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
                    controller.isFullScreen.value
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    color: Colors.white,
                  ),
                ),
                onPressed: () async {
                  if (controller.isFullScreen.value) {
                    controller.exitFullscreen();
                  } else {
                    controller.enterFullscreen();
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
