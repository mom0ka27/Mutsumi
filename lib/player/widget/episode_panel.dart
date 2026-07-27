import 'package:flutter/material.dart';

import '../../core/extensions/build_context.dart';
import '../../core/platform/app_platform.dart';
import '../model/episode_menu.dart';

class PlayerEpisodePanel extends StatelessWidget {
  const PlayerEpisodePanel({
    super.key,
    required this.visible,
    required this.position,
    required this.menu,
    required this.playingStream,
    required this.initiallyPlaying,
    required this.onSelected,
    required this.onClose,
  });

  final bool visible;
  final Animation<Offset> position;
  final PlayerEpisodeMenu menu;
  final Stream<bool> playingStream;
  final bool initiallyPlaying;
  final ValueChanged<int> onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safeArea = MediaQuery.viewPaddingOf(context);
    final compact = context.isCompactHeight;
    final desktop = AppPlatform.isDesktop;
    final panelInset = desktop ? 16.0 : 10.0;
    final availableWidth = size.width - safeArea.left - safeArea.right;
    final width = (availableWidth * (desktop ? 0.4 : 0.42)).clamp(
      300.0,
      desktop ? 400.0 : 360.0,
    );
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => onClose(),
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
            Positioned(
              top: panelInset,
              right: panelInset,
              bottom: panelInset,
              width: width,
              child: SlideTransition(
                position: position,
                child: SafeArea(
                  left: false,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Material(
                      color: Colors.transparent,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.black.withValues(alpha: 0.82),
                              Colors.black.withValues(alpha: 0.68),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 16 : 20,
                            compact ? 14 : 18,
                            compact ? 16 : 20,
                            compact ? 14 : 18,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.video_library_rounded,
                                      color: colorScheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '选集  ${menu.selectedIndex + 1} / ${menu.items.length}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          menu.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.white60),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: onClose,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white70,
                                    ),
                                    tooltip: '关闭',
                                  ),
                                ],
                              ),
                              SizedBox(height: compact ? 12 : 16),
                              Divider(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              SizedBox(height: compact ? 10 : 14),
                              Expanded(
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: menu.items.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) =>
                                      _PlayerEpisodeTile(
                                        item: menu.items[index],
                                        selected: index == menu.selectedIndex,
                                        playingStream: playingStream,
                                        initiallyPlaying: initiallyPlaying,
                                        onTap: index == menu.selectedIndex
                                            ? null
                                            : () => onSelected(index),
                                      ),
                                ),
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
          ],
        ),
      ),
    );
  }
}

class _PlayerEpisodeTile extends StatelessWidget {
  const _PlayerEpisodeTile({
    required this.item,
    required this.selected,
    required this.playingStream,
    required this.initiallyPlaying,
    required this.onTap,
  });

  final PlayerEpisodeItem item;
  final bool selected;
  final Stream<bool> playingStream;
  final bool initiallyPlaying;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? colorScheme.onPrimaryContainer : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: Colors.white.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '第 ${item.number} 集',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selected ? foreground : Colors.white60,
                        fontWeight: selected ? FontWeight.w700 : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: selected ? FontWeight.w700 : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                StreamBuilder<bool>(
                  stream: playingStream,
                  initialData: initiallyPlaying,
                  builder: (context, snapshot) => _PlayingIndicator(
                    color: colorScheme.primary,
                    playing: snapshot.data ?? false,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator({required this.color, required this.playing});

  final Color color;
  final bool playing;

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      animationBehavior: AnimationBehavior.preserve,
    );
    if (widget.playing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_PlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) {
      return;
    }
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final phase = _controller.value * 3;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (index) {
              final value = (phase + index * 0.72) % 3;
              final normalized = value <= 1.5 ? value / 1.5 : (3 - value) / 1.5;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 3,
                  height: widget.playing ? 5 + normalized * 12 : 3,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
