import '../extension/duration.dart';
import '../controller.dart';
import '../model/dandanplay_repository.dart';
import '../../core/platform/app_platform.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

class BottomBar extends StatelessWidget {
  final IndexPlayerController controller;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onToggleEpisodes;
  final bool allowFullscreenToggle;

  const BottomBar({
    super.key,
    required this.controller,
    this.onPreviousEpisode,
    this.onNextEpisode,
    this.onToggleEpisodes,
    this.allowFullscreenToggle = false,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primaryFixed;
    final dandanPlayConfigured = Get.find<DandanPlayRepository>().isConfigured;
    final safeArea = MediaQuery.viewPaddingOf(context);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final mobilePortrait = AppPlatform.isMobile && !landscape;
    final controlGap = AppPlatform.isDesktop ? 10.0 : 2.0;
    final compactControlGap = AppPlatform.isDesktop ? 4.0 : 0.0;
    final progressPadding = AppPlatform.isDesktop ? 8.0 : 4.0;
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
            padding: EdgeInsets.symmetric(horizontal: progressPadding),
            child: Obx(() {
              return ProgressBar(
                progress: controller.sliderPosition.value,
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
              Obx(
                () => controller.seeking
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
                          controller.state.playing
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                        ),
                      ),
              ),
              if (controller.isFullScreen.value)
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: onPreviousEpisode,
                  tooltip: '上一集',
                ),
              if (controller.isFullScreen.value)
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  onPressed: onNextEpisode,
                  tooltip: '下一集',
                ),
              SizedBox(width: controlGap),
              Obx(() {
                final duration = controller.state.duration;
                return Text(
                  "${controller.sliderPosition.value.str} / ${duration > Duration.zero ? duration.str : '--:--'}",
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
              SizedBox(width: controlGap),
              Builder(
                builder: (buttonContext) => Obx(
                  () => Tooltip(
                    message: '播放速度',
                    child: IconButton(
                      onPressed: () =>
                          _showSpeedPicker(buttonContext, accentColor),
                      icon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.speed_rounded, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(
                            '${controller.playbackSpeed.value.toStringAsFixed(controller.playbackSpeed.value % 1 == 0 ? 0 : 2)}×',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: compactControlGap),
              Obx(() {
                final tracks = controller.state.subtitles;
                final selected = controller.state.subtitle;
                return Builder(
                  builder: (buttonContext) => IconButton(
                    tooltip: '选择字幕',
                    onPressed: tracks.length > 1
                        ? () => _showSubtitlePicker(buttonContext, accentColor)
                        : null,
                    icon: Icon(
                      selected?.disabled == true
                          ? Icons.closed_caption_disabled_outlined
                          : Icons.closed_caption_rounded,
                      color: selected?.disabled == true
                          ? Colors.white70
                          : Colors.white,
                    ),
                  ),
                );
              }),
              SizedBox(width: controlGap),
              if (onToggleEpisodes != null && !mobilePortrait)
                IconButton(
                  onPressed: onToggleEpisodes,
                  icon: const Icon(
                    Icons.video_library_rounded,
                    color: Colors.white,
                  ),
                  tooltip: '选集',
                ),
              if (!mobilePortrait) SizedBox(width: controlGap),
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

  Future<void> _showSpeedPicker(BuildContext context, Color accentColor) {
    return _showPicker<double>(
      context: context,
      accentColor: accentColor,
      items: controller.options.availableSpeeds.map((speed) {
        final selected = controller.playbackSpeed.value == speed;
        return PopupMenuItem(
          value: speed,
          child: _PlayerMenuOption(
            selected: selected,
            accentColor: accentColor,
            leading: Icon(
              Icons.speed_rounded,
              color: selected ? accentColor : Colors.white70,
            ),
            label: '${speed.toStringAsFixed(2)}×',
          ),
        );
      }).toList(),
      onSelected: controller.setSpeed,
    );
  }

  Future<void> _showSubtitlePicker(BuildContext context, Color accentColor) {
    return _showPicker<PlayerSubtitleTrack>(
      context: context,
      accentColor: accentColor,
      items: controller.state.subtitles.map((track) {
        final selected = controller.state.subtitle?.id == track.id;
        return PopupMenuItem(
          value: track,
          child: _PlayerMenuOption(
            selected: selected,
            accentColor: accentColor,
            leading: Icon(
              track.disabled
                  ? Icons.closed_caption_disabled_outlined
                  : Icons.subtitles_rounded,
              color: selected ? accentColor : Colors.white70,
            ),
            label: _subtitleLabel(track),
          ),
        );
      }).toList(),
      onSelected: controller.setSubtitleTrack,
    );
  }

  Future<void> _showPicker<T>({
    required BuildContext context,
    required Color accentColor,
    required List<PopupMenuEntry<T>> items,
    required Future<void> Function(T value) onSelected,
  }) async {
    final selected = await showMenu<T>(
      context: context,
      position: _menuPosition(context),
      color: const Color(0xFF19191D),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      items: items,
    );
    if (selected != null) await onSelected(selected);
  }

  RelativeRect _menuPosition(BuildContext context) {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = button.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromRect(
      position & button.size,
      Offset.zero & overlay.size,
    );
  }
}

class _PlayerMenuOption extends StatelessWidget {
  const _PlayerMenuOption({
    required this.selected,
    required this.accentColor,
    required this.leading,
    required this.label,
  });

  final bool selected;
  final Color accentColor;
  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              SizedBox(width: 28, child: Center(child: leading)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: accentColor, size: 21),
            ],
          ),
        ),
      ),
    );
  }
}
