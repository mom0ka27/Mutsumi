import '../extension/duration.dart';
import '../controller.dart';
import '../model/dandanplay_repository.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

class BottomBar extends StatelessWidget {
  final IndexPlayerController controller;

  const BottomBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primaryFixed;
    final dandanPlayConfigured = Get.find<DandanPlayRepository>().isConfigured;
    return Container(
      padding: controller.isFullScreen.value
          ? EdgeInsets.symmetric(horizontal: 40, vertical: 8)
          : EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
            child: Obx(() {
              controller.revision;
              return ProgressBar(
                progress: controller.sliderPostion.value,
                total: controller.state.duration,
                buffered: controller.state.buffer,
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
              );
            }),
          ),
          Row(
            children: [
              StreamBuilder<bool>(
                stream: controller.playingStream,
                initialData: controller.state.playing,
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
                  "${controller.sliderPostion.value.str} / ${controller.state.duration.str}",
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
                  enabled: dandanPlayConfigured,
                  selected:
                      dandanPlayConfigured && controller.enableDanmaku.value,
                  child: InkWell(
                    onTap: dandanPlayConfigured
                        ? controller.toggleDanmaku
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color:
                            dandanPlayConfigured &&
                                controller.enableDanmaku.value
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: controller.danmakuCount.value == -1
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              dandanPlayConfigured
                                  ? '弹 ${controller.danmakuCount.value}'
                                  : '弹',
                              style: TextStyle(
                                color:
                                    dandanPlayConfigured &&
                                        controller.enableDanmaku.value
                                    ? Colors.black
                                    : Colors.white.withValues(
                                        alpha: dandanPlayConfigured ? 1 : 0.4,
                                      ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Obx(() {
                controller.revision;
                final tracks = controller.state.subtitles;
                final selected = controller.state.subtitle;
                return PopupMenuButton<PlayerSubtitleTrack>(
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
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  icon: Icon(
                    selected?.disabled == true
                        ? Icons.closed_caption_disabled_outlined
                        : Icons.closed_caption_rounded,
                    color: selected?.disabled == true
                        ? Colors.white70
                        : Colors.white,
                  ),
                );
              }),
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

  String _subtitleLabel(PlayerSubtitleTrack track) {
    if (track.disabled) {
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
