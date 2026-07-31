import 'dart:async';
import 'dart:ui';

import 'package:mutsumi/constants.dart';

import 'extension/duration.dart';
import 'model/episode_menu.dart';
import 'widget/top_bar.dart';
import 'controller.dart';
import 'player_keyboard.dart';
import 'player_interaction_state.dart';
import 'widget/bottom_bar.dart';
import 'widget/episode_panel.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:erika_flutter/erika_flutter.dart';
import 'package:ns_danmaku/ns_danmaku.dart';

class IndexPlayer extends StatefulWidget {
  final IndexPlayerController controller;
  final bool useOverlay;
  final bool autoplayNextEpisode;
  final bool allowFullscreenToggle;
  final bool closePageOnBack;

  const IndexPlayer(
    this.controller, {
    super.key,
    this.useOverlay = false,
    this.autoplayNextEpisode = false,
    this.allowFullscreenToggle = false,
    this.closePageOnBack = false,
  });

  @override
  State<IndexPlayer> createState() => _IndexPlayerState();

  static void init() {}
}

class _IndexPlayerState extends State<IndexPlayer>
    with SingleTickerProviderStateMixin {
  late final PlayerInteractionState _interaction;
  late final FocusNode _keyboardFocusNode;
  late final AnimationController _episodePanelController;
  late final Animation<Offset> _episodePanelOffset;
  DanmakuController? _danmakuController;
  StreamSubscription<void>? _completedSubscription;
  bool _episodePanelVisible = false;
  bool _advancingEpisode = false;

  @override
  void initState() {
    super.initState();
    _interaction = PlayerInteractionState(widget.controller);
    _keyboardFocusNode = FocusNode(debugLabel: 'IndexPlayerKeyboard');
    _completedSubscription = widget.controller.completedStream.listen((_) {
      if (widget.autoplayNextEpisode) {
        unawaited(_playNextEpisode());
      }
    });
    _episodePanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 240),
      animationBehavior: AnimationBehavior.preserve,
    );
    _episodePanelOffset =
        Tween<Offset>(begin: const Offset(1.08, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _episodePanelController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
  }

  @override
  void dispose() {
    _interaction.dispose();
    _keyboardFocusNode.dispose();
    _completedSubscription?.cancel();
    _episodePanelController.dispose();
    if (_danmakuController != null) {
      widget.controller.clearDanmakuController(_danmakuController!);
    }
    super.dispose();
  }

  void _toggleEpisodePanel() {
    if (_episodePanelVisible) {
      _closeEpisodePanel();
      return;
    }
    setState(() => _episodePanelVisible = true);
    _episodePanelController.forward(from: 0);
  }

  void _closeEpisodePanel() {
    if (!_episodePanelVisible) {
      return;
    }
    setState(() => _episodePanelVisible = false);
    _episodePanelController.reverse();
  }

  Future<void> _selectEpisode(int index) async {
    if (index == widget.controller.selectedIndex.value) {
      return;
    }
    await widget.controller.selectIndex(index);
  }

  Future<void> _playNextEpisode() async {
    if (_advancingEpisode || !widget.controller.hasNext) {
      return;
    }
    _advancingEpisode = true;
    try {
      await widget.controller.next();
    } finally {
      _advancingEpisode = false;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent && key == LogicalKeyboardKey.arrowRight) {
      final wasSuperSpeed = _interaction.cancelSuperSpeed();
      if (!wasSuperSpeed) {
        unawaited(widget.controller.seekBy(const Duration(seconds: 5)));
        _interaction.showControlsTemporarily();
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (_episodePanelVisible ||
        focusedContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final action = playerKeyboardActionFor(key);
    if (action == PlayerKeyboardAction.togglePlayback) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      unawaited(widget.controller.togglePlayback());
    } else if (action == PlayerKeyboardAction.seekBackward) {
      unawaited(widget.controller.seekBy(const Duration(seconds: -5)));
    } else if (action == PlayerKeyboardAction.seekForward) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _interaction.scheduleSuperSpeed();
    } else if (action == PlayerKeyboardAction.volumeUp) {
      unawaited(widget.controller.adjustVolume(0.05));
    } else if (action == PlayerKeyboardAction.volumeDown) {
      unawaited(widget.controller.adjustVolume(-0.05));
    } else {
      return KeyEventResult.ignored;
    }
    _interaction.showControlsTemporarily();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => widget.controller.isFullScreen.value
          ? SizedBox(
              height: MediaQuery.of(context).size.height,
              child: _buildContent(),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(context).width;
                final maxHeight = constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : double.infinity;
                final width = maxHeight.isFinite
                    ? maxWidth.clamp(0.0, maxHeight / 9 * 16).toDouble()
                    : maxWidth;
                final height = width / 16 * 9;
                return SizedBox(
                  width: width,
                  height: height,
                  child: _buildContent(),
                );
              },
            ),
    );
  }

  Widget _buildContent() {
    final selectedIndex = widget.controller.selectedIndex.value;
    final episodeMenu = selectedIndex == null
        ? null
        : PlayerEpisodeMenu(
            title: widget.controller.playlist.title,
            items: widget.controller.playlist.items
                .map(
                  (item) => PlayerEpisodeItem(
                    id: item.id,
                    number: item.number,
                    title: item.title,
                  ),
                )
                .toList(growable: false),
            selectedIndex: selectedIndex,
          );
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onFocusChange: (focused) {
        if (!focused) _interaction.cancelSuperSpeed();
      },
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          widget.useOverlay
              ? ErikaWindowOverlayVideoView(
                  key: widget.controller.videoKey,
                  player: widget.controller.player,
                )
              : ErikaVideoView(
                  key: widget.controller.videoKey,
                  player: widget.controller.player,
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
                    widget.controller.sliderPosition.value.inMilliseconds;
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
            child: BottomBar(
              controller: widget.controller,
              onPreviousEpisode:
                  episodeMenu != null && episodeMenu.selectedIndex > 0
                  ? () => widget.controller.previous()
                  : null,
              onNextEpisode:
                  episodeMenu != null &&
                      episodeMenu.selectedIndex < episodeMenu.items.length - 1
                  ? () => widget.controller.next()
                  : null,
              onToggleEpisodes: episodeMenu == null
                  ? null
                  : _toggleEpisodePanel,
              allowFullscreenToggle: widget.allowFullscreenToggle,
            ),
          ),
          _PlayerControlsOverlay(
            alignment: Alignment.topCenter,
            controller: widget.controller,
            visible: _interaction.showControls,
            child: TopBar(
              controller: widget.controller,
              closePageOnBack: widget.closePageOnBack,
            ),
          ),
          _PlayerStatusOverlay(
            alignment: Alignment(0, -0.8),
            visible: _interaction.superSpeed,
            childBuilder: () => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.fast_forward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.controller.options.longPressSpeed.toStringAsFixed(1)}× 倍速播放',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          _PlayerStatusOverlay(
            alignment: Alignment(0, -0.8),
            visible: widget.controller.wantSeeking,
            childBuilder: () => Text(
              '${widget.controller.state.position.str}  →  ${widget.controller.sliderPosition.value.str}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (episodeMenu != null && !_episodePanelVisible)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) < -200) {
                    _toggleEpisodePanel();
                  }
                },
              ),
            ),
          if (episodeMenu != null)
            PlayerEpisodePanel(
              visible: _episodePanelVisible,
              position: _episodePanelOffset,
              menu: episodeMenu,
              controller: widget.controller,
              onSelected: (index) => _selectEpisode(index),
              onClose: _closeEpisodePanel,
            ),
        ],
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
        () => AnimatedOpacity(
          opacity: visible.value ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(ignoring: !visible.value, child: child),
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
