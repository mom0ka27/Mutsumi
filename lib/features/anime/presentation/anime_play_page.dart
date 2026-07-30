import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/platform/app_platform.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../../player/player.dart';
import '../data/anime_service.dart';
import 'anime_play_controller.dart';

class AnimePlayPage extends StatefulWidget {
  const AnimePlayPage({
    super.key,
    required this.anime,
    required this.episodes,
    required this.initialEpisode,
  });

  final AnimeRead anime;
  final List<AnimeEpisodeRead> episodes;
  final int initialEpisode;

  @override
  State<AnimePlayPage> createState() => _AnimePlayPageState();
}

class _AnimePlayPageState extends State<AnimePlayPage>
    with WidgetsBindingObserver {
  final _controller = Get.find<AnimePlayController>();
  final _episodeScrollController = ScrollController();
  bool _disposed = false;
  bool _landscapeFullscreenRequested = false;

  AnimePlayController get controller => _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.episodes.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && AppPlatform.isMobile) {
        unawaited(_scrollToInitialEpisode());
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _episodeScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.handleAppLifecycleState(state);
  }

  void _enterFullscreenForLandscape() {
    if (_disposed) {
      return;
    }
    unawaited(_controller.enterFullscreenForLandscape());
  }

  Future<void> _scrollToInitialEpisode() async {
    if (!_episodeScrollController.hasClients || widget.episodes.isEmpty) return;
    final index = widget.initialEpisode.clamp(0, widget.episodes.length - 1);
    final viewportWidth = _episodeScrollController.position.viewportDimension;
    final target = (index * 170 + 80 - viewportWidth / 2)
        .clamp(0.0, _episodeScrollController.position.maxScrollExtent)
        .toDouble();
    final distance = (target - _episodeScrollController.offset).abs();
    if (distance < 1) return;
    final duration = Duration(
      milliseconds: (240 + distance * 0.22).round().clamp(280, 850),
    );
    await _episodeScrollController.animateTo(
      target,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.episodes.isEmpty) {
        return const Center(child: Text('暂无剧集'));
      }
      final mobile = AppPlatform.isMobile;
      final landscape = context.isLandscape;
      if (mobile && !landscape) {
        _landscapeFullscreenRequested = false;
      }
      if (mobile && landscape && !_landscapeFullscreenRequested) {
        _landscapeFullscreenRequested = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _enterFullscreenForLandscape(),
        );
      }
      final playerController = controller.playerController;
      final fullScreen = playerController.isFullScreen.value;
      if (fullScreen) {
        return PopScope(
          canPop: !mobile,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              return;
            }
            if (mobile) {
              unawaited(playerController.exitFullscreen());
            }
          },
          child: Material(
            type: MaterialType.transparency,
            child: IndexPlayer(
              playerController,
              useOverlay: true,
              allowFullscreenToggle: mobile,
              closePageOnBack: !mobile,
              autoplayNextEpisode: true,
            ),
          ),
        );
      }
      return GlassScaffold(
        enableBackgroundSampling: true,
        background: const AppGlassBackground(),
        settings: AppGlassSettings.standard(context),
        body: _portraitBody(context),
      );
    });
  }

  /// 竖屏：画面在上、信息和选集在下，选集横向滚动。
  Widget _portraitBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 黑色铺到状态栏底下，画面本身再靠 SafeArea 让开。
        ColoredBox(
          color: Colors.black,
          child: SafeArea(
            bottom: false,
            child: IndexPlayer(
              controller.playerController,
              useOverlay: false,
              allowFullscreenToggle: AppPlatform.isMobile,
              autoplayNextEpisode: true,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: _episodeHeader(context),
            ),
            Obx(() => _portraitEpisodeSelector(context)),
          ],
        ),
      ],
    );
  }

  Widget _episodeHeader(BuildContext context) {
    return Obx(() {
      final episode = controller.episode;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.anime.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '第 ${episode.index} 集 · ${episode.displayName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    });
  }

  Widget _portraitEpisodeSelector(BuildContext context) {
    final playerController = controller.playerController;
    final selectedIndex = playerController.selectedIndex.value;
    final loadingIndex = playerController.loadingIndex.value;
    return SingleChildScrollView(
      controller: _episodeScrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 20),
          ...List.generate(widget.episodes.length, (index) {
            final episode = widget.episodes[index];
            final selected = index == selectedIndex;
            final loading = index == loadingIndex;
            return Padding(
              padding: EdgeInsets.only(
                right: index == widget.episodes.length - 1 ? 0 : 10,
              ),
              child: GlassCard(
                width: 160,
                padding: EdgeInsets.zero,
                shape: const LiquidRoundedSuperellipse(borderRadius: 16),
                child: InkWell(
                  onTap: selected || loading
                      ? null
                      : () => unawaited(playerController.selectIndex(index)),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.18)
                          : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: selected ? 1.5 : 0,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '第 ${episode.index} 集',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: selected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : null,
                                    ),
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.play_circle_fill_rounded,
                                size: 17,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          episode.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                                fontWeight: selected ? FontWeight.w800 : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          SizedBox(width: 20),
        ],
      ),
    );
  }
}
