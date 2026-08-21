import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../anime/data/anime_models.dart';
import '../data/subscription_models.dart';
import '../data/subscription_service.dart';

class SubscriptionEditorPage extends StatefulWidget {
  const SubscriptionEditorPage({
    super.key,
    required this.anime,
    this.existing,
    this.service,
  });

  final AnimeRead anime;
  final SubscriptionRead? existing;
  final SubscriptionService? service;

  @override
  State<SubscriptionEditorPage> createState() => _SubscriptionEditorPageState();
}

class _SubscriptionEditorPageState extends State<SubscriptionEditorPage> {
  late final SubscriptionService _service =
      widget.service ?? Get.find<SubscriptionService>();
  final _selectedFansubs = <String>{};
  final _orderedFansubs = <String>[];
  List<FansubCandidateRead> _candidates = const [];
  List<PreferenceProfileRead> _profiles = const [];
  SubscriptionPreviewRead? _preview;
  int? _profileId;
  bool _allowNoFansub = false;
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _selectedFansubs.addAll(existing?.fansubs ?? const []);
    _orderedFansubs.addAll(existing?.fansubs ?? const []);
    _allowNoFansub = existing?.allowNoFansub ?? false;
    _enabled = existing?.enabled ?? true;
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final profiles = await _service.listProfiles();
      final candidates = await _service.listFansubs(widget.anime.bangumiId);
      if (!mounted) return;
      final options = candidates
          .where((candidate) => !candidate.isNoFansub)
          .map((candidate) => candidate.name)
          .toList();
      for (final option in options) {
        if (!_orderedFansubs.contains(option)) {
          _orderedFansubs.add(option);
        }
      }
      _profiles = profiles;
      _candidates = candidates;
      _profileId =
          widget.existing?.profileId ??
          profiles.firstWhereOrNull((profile) => profile.isDefault)?.id ??
          (profiles.isEmpty ? null : profiles.first.id);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      await showErrorDialog(
        title: '加载订阅选项失败',
        message: errorMessageOf(error),
        error: error,
      );
    }
  }

  Future<void> _save() async {
    final profileId = _profileId;
    if (profileId == null || _saving) return;
    if (_selectedFansubs.isEmpty && !_allowNoFansub) {
      await showInfoDialog(
        title: '请选择字幕组',
        message: '至少选择一个字幕组，或打开“允许无字幕组资源”。',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await _service.createSubscription(
          animeId: widget.anime.id,
          profileId: profileId,
          fansubs: _selectedFansubsInOrder,
          allowNoFansub: _allowNoFansub,
        );
      } else {
        await _service.updateSubscription(
          subscriptionId: widget.existing!.id,
          profileId: profileId,
          fansubs: _selectedFansubsInOrder,
          allowNoFansub: _allowNoFansub,
          enabled: _enabled,
        );
      }
      if (mounted) Get.back(result: true);
    } catch (error) {
      if (!mounted) return;
      await showErrorDialog(
        title: '保存订阅失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消追番'),
        content: Text('确定取消“${widget.anime.displayName}”的自动追番吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('取消追番'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _service.deleteSubscription(existing.id);
      if (mounted) Get.back(result: true);
    } catch (error) {
      if (!mounted) return;
      await showErrorDialog(
        title: '取消追番失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _previewRules() async {
    final profileId = _profileId;
    if (profileId == null || _previewing) return;
    setState(() => _previewing = true);
    try {
      final preview = await _service.previewSubscription(
        animeId: widget.anime.id,
        profileId: profileId,
        fansubs: _selectedFansubsInOrder,
        allowNoFansub: _allowNoFansub,
      );
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (!mounted) return;
      await showErrorDialog(
        title: '预览失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  List<String> get _selectedFansubsInOrder =>
      _orderedFansubs.where(_selectedFansubs.contains).toList(growable: false);

  void _toggleFansub(String name) {
    setState(() {
      if (!_selectedFansubs.remove(name)) {
        _selectedFansubs.add(name);
      }
      _preview = null;
    });
  }

  void _reorderFansub(int oldIndex, int newIndex) {
    setState(() {
      final item = _orderedFansubs.removeAt(oldIndex);
      _orderedFansubs.insert(newIndex, item);
      _preview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '添加追番' : '追番设置'),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: '取消追番',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.notifications_off_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  widget.anime.displayName,
                  style: theme.textTheme.headlineSmall,
                ),
                if (widget.anime.originalName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.anime.originalName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                DropdownButtonFormField<int>(
                  key: ValueKey(_profileId),
                  initialValue: _profileId,
                  decoration: const InputDecoration(
                    labelText: '偏好配置',
                    border: OutlineInputBorder(),
                  ),
                  items: _profiles
                      .map(
                        (profile) => DropdownMenuItem<int>(
                          value: profile.id,
                          child: Text(_profileLabel(profile)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _profileId = value;
                    _preview = null;
                  }),
                ),
                if (widget.existing != null) ...[
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用自动追番'),
                    value: _enabled,
                    onChanged: (value) => setState(() {
                      _enabled = value;
                      _preview = null;
                    }),
                  ),
                ],
                const SizedBox(height: 20),
                Text('字幕组优先级', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${_selectedFansubs.length} 个已选择 · 上方优先',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (_orderedFansubs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('最近没有找到字幕组资源'),
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _orderedFansubs.length,
                    onReorderItem: _reorderFansub,
                    itemBuilder: (context, index) {
                      final name = _orderedFansubs[index];
                      final candidate = _candidates.firstWhereOrNull(
                        (item) => item.name == name,
                      );
                      return CheckboxListTile(
                        key: ValueKey(name),
                        value: _selectedFansubs.contains(name),
                        onChanged: (_) => _toggleFansub(name),
                        title: Text(name),
                        subtitle: candidate == null
                            ? null
                            : Text('${candidate.count} 条近期资源'),
                        secondary: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                if (_candidates.any((candidate) => candidate.isNoFansub))
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('允许无字幕组资源'),
                    subtitle: Text(
                      '${_candidates.firstWhere((candidate) => candidate.isNoFansub).count} 条近期资源',
                    ),
                    value: _allowNoFansub,
                    onChanged: (value) => setState(() {
                      _allowNoFansub = value;
                      _preview = null;
                    }),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _previewing ? null : _previewRules,
                  icon: _previewing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_outlined),
                  label: const Text('预览最近资源'),
                ),
                if (_preview != null) _previewSection(theme),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(widget.existing == null ? '开始追番' : '保存设置'),
                ),
              ],
            ),
    );
  }

  Widget _previewSection(ThemeData theme) {
    final preview = _preview!;
    final visible = preview.candidates.take(20).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '预览 · ${preview.resourceCount} 条资源 · ${preview.acceptedCount} 条通过硬过滤',
                style: theme.textTheme.titleSmall,
              ),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('没有可用候选'),
                )
              else
                ...visible.map(
                  (candidate) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      candidate.selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: candidate.selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    title: Text(
                      candidate.episodeIndex == null
                          ? candidate.resourceTitle
                          : '第 ${candidate.episodeIndex} 集 · ${candidate.fansub.isEmpty ? '无字幕组' : candidate.fansub}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${candidate.score.toStringAsFixed(2)} · ${candidate.reason ?? candidate.state}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _profileLabel(PreferenceProfileRead profile) {
    final mode = profile.languageMode == 'any' ? '不限字形' : profile.languageMode;
    return '${profile.name} · $mode';
  }
}
