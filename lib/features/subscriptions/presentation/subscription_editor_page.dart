import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../constants.dart';
import '../../../core/extensions/build_context.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/media_summary_card.dart';
import '../../bangumi/data/airing_status.dart';
import '../data/subscription_models.dart';
import '../data/subscription_service.dart';

class SubscriptionEditorPage extends StatefulWidget {
  /// Identified by [bangumiId] rather than by a library anime: the whole point
  /// of following a show is that it may not be in the library yet.
  const SubscriptionEditorPage({
    super.key,
    required this.bangumiId,
    required this.title,
    this.subtitle = '',
    this.status = AiringStatus.unknown,
    this.existing,
    this.service,
  });

  final int bangumiId;
  final String title;
  final String subtitle;
  final AiringStatus status;
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
  bool _backfillAired = false;
  bool _loading = true;
  bool _saving = false;
  bool _previewing = false;
  bool _previewStale = false;
  String? _previewError;

  bool get _isNew => widget.existing == null;

  /// Nothing to catch up on before a show starts, so the switch only exists
  /// once it has aired at all.
  bool get _canBackfill => _isNew && widget.status != AiringStatus.unaired;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _selectedFansubs.addAll(existing?.fansubs ?? const []);
    _orderedFansubs.addAll(existing?.fansubs ?? const []);
    _allowNoFansub = existing?.allowNoFansub ?? false;
    _enabled = existing?.enabled ?? true;
    // On by default: following a show that is already airing almost always
    // means wanting the episodes broadcast so far, not just the next one.
    _backfillAired = _canBackfill;
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final profiles = await _service.listProfiles();
      final candidates = await _service.listFansubs(widget.bangumiId);
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
      // Run unprompted: how much of the season has aired is the first thing
      // this page has to answer, and it costs the same query as the button.
      await _previewRules(silent: true);
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
          bangumiId: widget.bangumiId,
          profileId: profileId,
          fansubs: _selectedFansubsInOrder,
          allowNoFansub: _allowNoFansub,
          backfillAired: _backfillAired,
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
        content: Text('确定取消“${widget.title}”的自动追番吗？'),
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

  /// Ask the server what these rules would fetch right now.
  ///
  /// [silent] is for the automatic run on open: a modal is right when the user
  /// pressed a button, and just noise when they only opened the page.
  Future<void> _previewRules({bool silent = false}) async {
    final profileId = _profileId;
    if (profileId == null || _previewing) return;
    setState(() {
      _previewing = true;
      _previewError = null;
    });
    try {
      final preview = await _service.previewSubscription(
        bangumiId: widget.bangumiId,
        profileId: profileId,
        fansubs: _selectedFansubsInOrder,
        allowNoFansub: _allowNoFansub,
        backfillAired: _backfillAired,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _previewStale = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _previewError = errorMessageOf(error));
      if (silent) return;
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

  FansubCandidateRead? get _noFansubCandidate =>
      _candidates.firstWhereOrNull((candidate) => candidate.isNoFansub);

  void _toggleFansub(String name) {
    setState(() {
      if (!_selectedFansubs.remove(name)) {
        _selectedFansubs.add(name);
      }
      // Marked stale rather than dropped: how much of the season has aired does
      // not depend on the rules, and it is the part worth keeping on screen.
      _previewStale = true;
    });
  }

  void _reorderFansub(int oldIndex, int newIndex) {
    setState(() {
      final item = _orderedFansubs.removeAt(oldIndex);
      _orderedFansubs.insert(newIndex, item);
      _previewStale = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassScaffold(
      topEdgeFade: true,
      bottomEdgeFade: false,
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        centerTitle: false,
        title: Text(
          _isNew ? '添加追番' : '追番设置',
          style: theme.textTheme.titleLarge,
        ),
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
        actions: [
          if (!_isNew)
            GlassButton(
              width: 40,
              height: 40,
              iconSize: 20,
              icon: const Icon(Icons.notifications_off_outlined),
              label: '取消追番',
              enabled: !_saving,
              onTap: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // 保存栏浮在内容之上，底部要多留出它的高度。
              padding: context.pageContentPadding(bottom: 116),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(theme),
                        const SizedBox(height: 24),
                        _basicsSection(theme),
                        const SizedBox(height: 24),
                        _fansubSection(theme),
                        const SizedBox(height: 24),
                        _previewSection(theme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomBar: _loading ? null : _saveBar(context, theme),
    );
  }

  Widget _header(ThemeData theme) {
    final status = _airingChip(widget.status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.headlineSmall),
          if (widget.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (status != null) ...[const SizedBox(height: 10), status],
        ],
      ),
    );
  }

  Widget _basicsSection(ThemeData theme) {
    return _Section(
      title: '追番方式',
      subtitle: '决定用哪套偏好规则挑选资源',
      child: _GlassPanel(
        child: _DividedColumn(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: DropdownButtonFormField<int>(
                key: ValueKey(_profileId),
                initialValue: _profileId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '偏好配置'),
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
                  _previewStale = true;
                }),
              ),
            ),
            if (!_isNew)
              _switchRow(
                title: '启用自动追番',
                subtitle: '关闭后保留设置，但不再自动抓取新集',
                value: _enabled,
                onChanged: (value) => setState(() {
                  _enabled = value;
                  _previewStale = true;
                }),
              ),
            if (_canBackfill)
              _switchRow(
                title: '补齐已播出的集',
                // Without this, joining mid-season only ever picks up the
                // last few days of resources.
                subtitle: '从首播日起扫一遍，而不是只看最近几天',
                value: _backfillAired,
                // Re-runs straight away: it changes which episodes the preview
                // can see at all, which is the number the user is reading.
                onChanged: (value) {
                  setState(() {
                    _backfillAired = value;
                    _previewStale = true;
                  });
                  _previewRules(silent: true);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _fansubSection(ThemeData theme) {
    final noFansub = _noFansubCandidate;
    return _Section(
      title: '字幕组优先级',
      subtitle: '${_selectedFansubs.length} 个已选择 · 上方优先',
      child: _GlassPanel(
        child: _DividedColumn(
          children: [
            if (_orderedFansubs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: Center(child: Text('最近没有找到字幕组资源')),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 4),
                buildDefaultDragHandles: false,
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
            if (noFansub != null)
              _switchRow(
                title: '允许无字幕组资源',
                subtitle: '${noFansub.count} 条近期资源',
                value: _allowNoFansub,
                onChanged: (value) => setState(() {
                  _allowNoFansub = value;
                  _previewStale = true;
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _previewSection(ThemeData theme) {
    final preview = _preview;
    return _Section(
      title: '已播出与匹配',
      subtitle: _isNew ? '保存后会立刻按这个结果开始下载' : '当前规则会挑中哪些资源',
      child: _GlassPanel(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview == null)
                _previewPlaceholder(theme)
              else
                _seasonSummary(theme, preview),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _previewing || _profileId == null
                    ? null
                    : _previewRules,
                icon: _previewing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(_previewStale ? '规则已改，重新匹配' : '重新匹配'),
              ),
              if (preview != null && !_previewStale) ...[
                const SizedBox(height: 8),
                Text(
                  '${preview.resourceCount} 条资源 · ${preview.acceptedCount} 条通过硬过滤',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (preview.candidates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('没有可用候选'),
                  )
                else
                  ...preview.candidates
                      .take(20)
                      .map((candidate) => _PreviewTile(candidate: candidate)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewPlaceholder(ThemeData theme) {
    final error = _previewError;
    if (_previewing) {
      return Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('正在查询已播出的集和可用资源', style: theme.textTheme.bodyMedium),
        ],
      );
    }
    return Text(
      error == null ? '还没有匹配结果' : '查询失败：$error',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: error == null
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.error,
      ),
    );
  }

  /// The season, then what the rules do with it.
  ///
  /// The aired count does not depend on the rules, so it survives a stale
  /// preview: it is the number that tells the user whether "nothing matched"
  /// means "nothing has aired" or "the rules are too narrow".
  Widget _seasonSummary(ThemeData theme, SubscriptionPreviewRead preview) {
    final aired = preview.airedEpisodeCount;
    final total = preview.episodeCount;
    final missing = preview.missingEpisodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total == 0
              ? '暂无集数信息'
              : aired == 0
              ? '还没有开播 · 共 $total 集'
              : '已播出 $aired 集 · 共 $total 集',
          style: theme.textTheme.titleSmall,
        ),
        if (preview.ownedEpisodeCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            '库里已有 ${preview.ownedEpisodeCount} 集',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (!_previewStale) ...[
          const SizedBox(height: 6),
          Text(
            preview.matchedEpisodes.isEmpty
                ? '当前规则没有匹配到任何一集'
                : '${_isNew ? '将下载' : '会下载'} ${preview.matchedEpisodes.length} 集：${_episodeRange(preview.matchedEpisodes)}',
            style: theme.textTheme.bodyMedium,
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '第 ${_episodeRange(missing)} 集已播出但没有匹配到资源',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _saveBar(BuildContext context, ThemeData theme) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: GlassCard(
            useOwnLayer: true,
            padding: const EdgeInsets.all(12),
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            settings: AppGlassSettings.standard(context),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      _selectionSummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving || _profileId == null ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _saving
                        ? '保存中'
                        : _isNew
                        ? '开始追番'
                        : '保存设置',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What the save bar says about the current selection.
  ///
  /// The button is the only thing that can be disabled, so the reason it is
  /// disabled has to live here.
  String get _selectionSummary {
    if (_profileId == null) return '没有可用的偏好配置';
    final count = _selectedFansubs.length;
    final fansubs = count == 0
        ? (_allowNoFansub ? '不限字幕组' : '未选择字幕组')
        : (_allowNoFansub ? '$count 个字幕组 · 含无字幕组' : '$count 个字幕组');
    final preview = _preview;
    if (preview == null || _previewStale || !_isNew) return fansubs;
    // What pressing the button will actually do, next to the button.
    return preview.matchedEpisodes.isEmpty
        ? '$fansubs · 暂无可下载的集'
        : '$fansubs · 立即下载 ${preview.matchedEpisodes.length} 集';
  }

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget? _airingChip(AiringStatus status) {
    return switch (status) {
      AiringStatus.unaired => const MediaInfoChip(
        icon: Icons.schedule_rounded,
        label: '未播出',
      ),
      AiringStatus.airing => const MediaInfoChip(
        icon: Icons.podcasts_rounded,
        label: '连载中',
      ),
      AiringStatus.finished => const MediaInfoChip(
        icon: Icons.check_circle_outline_rounded,
        label: '已完结',
      ),
      AiringStatus.unknown => null,
    };
  }

  String _profileLabel(PreferenceProfileRead profile) {
    final mode = profile.languageMode == 'any' ? '不限字形' : profile.languageMode;
    return '${profile.name} · $mode';
  }
}

/// Collapses consecutive episode numbers: `[1,2,3,5]` reads as `1-3, 5`.
///
/// A backfilled season is a dozen numbers, and listing them all turns the one
/// line the user has to read into a wall of digits.
String _episodeRange(List<int> indices) {
  if (indices.isEmpty) return '';
  final sorted = [...indices]..sort();
  final parts = <String>[];
  var start = sorted.first;
  var previous = start;
  for (final index in sorted.skip(1)) {
    if (index == previous + 1) {
      previous = index;
      continue;
    }
    parts.add(start == previous ? '$start' : '$start-$previous');
    start = index;
    previous = index;
  }
  parts.add(start == previous ? '$start' : '$start-$previous');
  return parts.join('、');
}

/// A titled block: label outside, controls inside a glass panel.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// The glass surface every section sits on.
///
/// The [Material] is what lets tiles inside draw their ink and drag proxies:
/// [GlassCard] is not one.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      useOwnLayer: true,
      padding: EdgeInsets.zero,
      shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
      settings: AppGlassSettings.standard(context),
      // 圆角裁剪交给 Material：行内的水波纹不会溢出到卡片圆角外面。
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.all(Constants.radius),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// Stacks rows with hairlines between them, skipping absent ones.
class _DividedColumn extends StatelessWidget {
  const _DividedColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          children[index],
        ],
      ],
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.candidate});

  final SubscriptionPreviewCandidateRead candidate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        candidate.selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: candidate.selected ? colorScheme.primary : colorScheme.outline,
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
    );
  }
}
