import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mutsumi/player/model/danmaku.dart';

import '../../core/formatters/date_formatter.dart';
import '../controller.dart';
import '../model/dandanplay_repository.dart';

class AdvancedOptionsSheet extends StatefulWidget {
  const AdvancedOptionsSheet({super.key, required this.controller});

  final IndexPlayerController controller;

  @override
  State<AdvancedOptionsSheet> createState() => _AdvancedOptionsSheetState();
}

class _AdvancedOptionsSheetState extends State<AdvancedOptionsSheet> {
  DanmakuCacheInfo? _cacheInfo;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final repo = Get.find<DandanPlayRepository>();
    final episodeId = widget.controller.danmakuEpisodeId.value;
    _cacheInfo = episodeId == null ? null : repo.getCacheInfo(episodeId);
  }

  Future<void> _clearDanmakuCache() async {
    final episodeId = widget.controller.danmakuEpisodeId.value;
    if (episodeId == null) return;
    await Get.find<DandanPlayRepository>().clearEpisodeCache(episodeId);
    if (mounted) {
      setState(() => _cacheInfo = null);
    }
  }

  Future<void> _refreshDanmakuCache() async {
    final episodeId = widget.controller.danmakuEpisodeId.value;
    if (episodeId == null) return;
    setState(() => _isRefreshing = true);
    try {
      await Get.find<DandanPlayRepository>().clearEpisodeCache(episodeId);
      await widget.controller.refreshDanmaku();
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _cacheInfo = Get.find<DandanPlayRepository>().getCacheInfo(episodeId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final sectionStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final dandanPlayConfigured = Get.find<DandanPlayRepository>().isConfigured;
    final provider = widget.controller.video.value?.danmakuProvider;
    final fileHash = provider is DandanPlayDanmakuProvider
        ? provider.fileHash
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Obx(
                () => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('调试 HUD'),
                  subtitle: const Text('在视频画面上显示 Erika 实时诊断信息'),
                  value: widget.controller.debugHudEnabled.value,
                  secondary: widget.controller.debugHudUpdating.value
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.monitor_heart_outlined),
                  onChanged: widget.controller.debugHudUpdating.value
                      ? null
                      : (enabled) async {
                          try {
                            await widget.controller.setDebugHudEnabled(enabled);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('调试 HUD 切换失败：$error')),
                              );
                            }
                          }
                        },
                ),
              ),
              const SizedBox(height: 16),
              _sectionHeader('弹幕缓存', sectionStyle),
              const SizedBox(height: 12),
              _infoRow(
                '弹弹Play API',
                dandanPlayConfigured ? '已配置' : '未配置',
                labelStyle,
                valueStyle,
              ),
              _infoRow('Hash', fileHash ?? '-', labelStyle, valueStyle),
              _infoRow(
                'Episode ID',
                widget.controller.danmakuEpisodeId.value?.toString() ?? '未匹配',
                labelStyle,
                valueStyle,
              ),
              _infoRow(
                '弹幕数量',
                widget.controller.danmakuCount.value >= 0
                    ? '${widget.controller.danmakuCount.value} 条'
                    : '无',
                labelStyle,
                valueStyle,
              ),
              if (_cacheInfo != null) ...[
                _infoRow(
                  '缓存时间',
                  _cacheInfo!.cachedAt.yyyyMMddHHmm,
                  labelStyle,
                  valueStyle,
                ),
                _infoRow(
                  '过期时间',
                  _cacheInfo!.expiresAt.yyyyMMddHHmm,
                  labelStyle,
                  valueStyle,
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed:
                    !_isRefreshing &&
                        widget.controller.danmakuEpisodeId.value != null
                    ? _refreshDanmakuCache
                    : null,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('更新当前集弹幕缓存'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _cacheInfo != null ? _clearDanmakuCache : null,
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('清理弹幕缓存'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, TextStyle? style) {
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: style?.color),
        const SizedBox(width: 8),
        Text(title, style: style),
      ],
    );
  }

  Widget _infoRow(
    String label,
    String value,
    TextStyle? labelStyle,
    TextStyle? valueStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,

        children: [
          SizedBox(width: 110, child: Text(label, style: labelStyle)),
          Expanded(child: Text(value, style: valueStyle)),
        ],
      ),
    );
  }
}
