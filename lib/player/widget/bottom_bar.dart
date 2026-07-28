import '../extension/duration.dart';
import '../controller.dart';
import '../model/dandanplay_repository.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

class BottomBar extends StatelessWidget {
  final IndexPlayerController controller;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onToggleEpisodes;
  final bool allowFullscreenToggle;

  const BottomBar({
    super.key,
    required this.controller,
    this.onNextEpisode,
    this.onToggleEpisodes,
    this.allowFullscreenToggle = false,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primaryFixed;
    final dandanPlayConfigured = Get.find<DandanPlayRepository>().isConfigured;
    final safeArea = MediaQuery.viewPaddingOf(context);
    final horizontalPadding = controller.isFullScreen.value
        ? EdgeInsets.only(
            left: safeArea.left.clamp(40.0, double.infinity).toDouble(),
            right: safeArea.right.clamp(40.0, double.infinity).toDouble(),
            top: 8,
            bottom: safeArea.bottom.clamp(8.0, double.infinity).toDouble(),
          )
        : const EdgeInsets.symmetric(horizontal: 4, vertical: 4);
    return Container(
      padding: horizontalPadding,
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
                      onPressed: onNextEpisode,
                      tooltip: '下一集',
                    )
                  : SizedBox(),
              const SizedBox(width: 10),
              Obx(() {
                controller.revision;
                final duration = controller.state.duration;
                return Text(
                  "${controller.sliderPostion.value.str} / ${duration > Duration.zero ? duration.str : '--:--'}",
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );
              }),
              const Spacer(),
              Semantics(
                label: '弹幕',
                button: true,
                enabled: dandanPlayConfigured,
                selected:
                    dandanPlayConfigured && controller.enableDanmaku.value,
                child: InkWell(
                  onTap: dandanPlayConfigured ? controller.toggleDanmaku : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color:
                          dandanPlayConfigured && controller.enableDanmaku.value
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Obx(
                      () => Text(
                        '弹 ${controller.danmakuCount.value}',
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
              if (onToggleEpisodes != null)
                IconButton(
                  onPressed: onToggleEpisodes,
                  icon: const Icon(
                    Icons.video_library_rounded,
                    color: Colors.white,
                  ),
                  tooltip: '选集',
                ),
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
              if (allowFullscreenToggle)
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
                      await controller.exitFullscreen();
                    } else {
                      await controller.enterFullscreen();
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
