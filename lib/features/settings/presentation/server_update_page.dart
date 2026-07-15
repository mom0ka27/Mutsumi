import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/server_update_service.dart';

class ServerUpdatePage extends StatefulWidget {
  const ServerUpdatePage({super.key});

  @override
  State<ServerUpdatePage> createState() => _ServerUpdatePageState();
}

class _ServerUpdatePageState extends State<ServerUpdatePage> {
  final _service = ServerUpdateService();
  var _channel = ServerUpdateChannel.release;
  ServerUpdateInfo? _info;
  String? _errorMessage;
  var _loading = true;
  var _applying = false;
  ServerUpdateStatusInfo? _updateStatus;
  Timer? _statusTimer;
  var _statusChecks = 0;
  late String _targetVersion;

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading && _info != null) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final info = await _service.getUpdate(_channel);
      if (mounted) setState(() => _info = info);
    } catch (error) {
      if (mounted) setState(() => _errorMessage = errorMessageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadChannel() async {
    try {
      _channel = await _service.getUpdateChannel();
    } catch (_) {
      _channel = ServerUpdateChannel.release;
    }
    if (mounted) _load();
  }

  Future<void> _apply() async {
    final info = _info;
    if (info == null || !info.updateAvailable) {
      return;
    }
    final confirmed = await showAppDialog<bool>(
      AlertDialog(
        title: const Text('确认更新服务端'),
        content: Text('将更新至 ${info.latestVersion}，服务会短暂重启。'),
        actions: [
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AppDialog.dismiss(context, false),
              child: const Text('取消'),
            ),
          ),
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppDialog.dismiss(context, true),
              child: const Text('更新'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _applying = true;
      _targetVersion = info.latestVersion;
      _updateStatus = null;
    });
    try {
      await _service.applyUpdate(_channel);
      _startStatusPolling();
    } catch (error) {
      if (mounted) {
        await showErrorDialog(title: '更新失败', message: errorMessageOf(error));
        setState(() => _applying = false);
      }
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusChecks = 0;
    _pollUpdateStatus();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollUpdateStatus(),
    );
  }

  Future<void> _pollUpdateStatus() async {
    if (!mounted || !_applying) return;
    _statusChecks++;
    if (_statusChecks > 120) {
      _statusTimer?.cancel();
      setState(() {
        _applying = false;
        _errorMessage = '等待服务端重启超时，请稍后手动刷新。';
      });
      return;
    }
    try {
      final status = await _service.getUpdateStatus();
      if (!mounted) return;
      setState(() => _updateStatus = status);
      if (status.status == ServerUpdateStatus.running) {
        if (await _confirmUpdatedVersion()) {
          _statusTimer?.cancel();
        }
      } else if (status.status == ServerUpdateStatus.failed) {
        _statusTimer?.cancel();
        setState(() {
          _applying = false;
          _errorMessage = status.message.isEmpty ? '服务端更新失败。' : status.message;
        });
      }
    } catch (_) {}
  }

  Future<bool> _confirmUpdatedVersion() async {
    try {
      final info = await _service.getUpdate(_channel);
      if (!mounted) return false;
      if (_versionsEqual(info.currentVersion, _targetVersion)) {
        setState(() {
          _applying = false;
          _info = info;
        });
        return true;
      }
    } catch (_) {}
    return false;
  }

  bool _versionsEqual(String left, String right) =>
      left.replaceFirst(RegExp(r'^v'), '') ==
      right.replaceFirst(RegExp(r'^v'), '');

  Future<void> _changeChannel(ServerUpdateChannel channel) async {
    if (_channel == channel) return;
    final previousChannel = _channel;
    setState(() {
      _channel = channel;
      _info = null;
    });
    try {
      await _service.setUpdateChannel(channel);
    } catch (error) {
      if (mounted) {
        setState(() {
          _channel = previousChannel;
          _errorMessage = errorMessageOf(error);
        });
      }
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('服务端更新', style: Theme.of(context).textTheme.titleLarge),
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
        actions: [
          GlassButton(
            width: 40,
            height: 40,
            iconSize: 20,
            icon: const Icon(Icons.refresh_rounded),
            label: '刷新',
            onTap: () {
              if (!_loading && !_applying) _load();
            },
          ),
        ],
        centerTitle: false,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, Constants.topPadding, 20, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _UpdateInfoCard(
            channel: _channel,
            info: _info,
            errorMessage: _errorMessage,
            loading: _loading,
            applying: _applying,
            updateStatus: _updateStatus,
            onChannelChanged: _changeChannel,
            onApply: _apply,
          ),
        ),
      ),
    );
  }
}

class _UpdateInfoCard extends StatelessWidget {
  const _UpdateInfoCard({
    required this.channel,
    required this.info,
    required this.errorMessage,
    required this.loading,
    required this.applying,
    required this.updateStatus,
    required this.onChannelChanged,
    required this.onApply,
  });

  final ServerUpdateChannel channel;
  final ServerUpdateInfo? info;
  final String? errorMessage;
  final bool loading;
  final bool applying;
  final ServerUpdateStatusInfo? updateStatus;
  final ValueChanged<ServerUpdateChannel> onChannelChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final updateInfo = info;
    final hasError = errorMessage != null;
    final canApply = updateInfo != null && updateInfo.updateAvailable;
    final title = _title(updateInfo, hasError);
    final description = _description(updateInfo, hasError);
    return GlassCard(
      useOwnLayer: true,
      padding: const EdgeInsets.all(24),
      shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
      settings: AppGlassSettings.standard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: hasError
                ? colors.errorContainer
                : updateInfo?.updateAvailable == true
                ? colors.primaryContainer
                : colors.secondaryContainer,
            foregroundColor: hasError
                ? colors.onErrorContainer
                : updateInfo?.updateAvailable == true
                ? colors.onPrimaryContainer
                : colors.onSecondaryContainer,
            child: Icon(
              hasError
                  ? Icons.error_outline_rounded
                  : updateInfo?.updateAvailable == true
                  ? Icons.system_update_rounded
                  : Icons.verified_rounded,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          SegmentedButton<ServerUpdateChannel>(
            segments: const [
              ButtonSegment(
                value: ServerUpdateChannel.release,
                icon: Icon(Icons.workspace_premium_outlined),
                label: Text('Release'),
              ),
              ButtonSegment(
                value: ServerUpdateChannel.prerelease,
                icon: Icon(Icons.science_outlined),
                label: Text('Beta'),
              ),
              ButtonSegment(
                value: ServerUpdateChannel.branch,
                icon: Icon(Icons.account_tree_outlined),
                label: Text('main'),
              ),
            ],
            selected: {channel},
            onSelectionChanged: loading || applying
                ? null
                : (values) => onChannelChanged(values.first),
          ),
          const SizedBox(height: 24),
          _VersionRow(
            label: '当前版本',
            value: hasError ? '检查失败' : updateInfo?.currentVersion ?? '检查中...',
          ),
          const SizedBox(height: 12),
          _VersionRow(
            label: '最新版本',
            value: hasError ? '检查失败' : updateInfo?.latestVersion ?? '检查中...',
            highlighted: updateInfo?.updateAvailable == true,
          ),
          if (hasError) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.all(Constants.radius),
              ),
              child: Text(
                errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
          ],
          if (applying) ...[
            const SizedBox(height: 16),
            _UpdateProgressStatus(status: updateStatus),
          ],
          if (updateInfo != null) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            Text('发布信息', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              updateInfo.releaseName.isEmpty
                  ? '未提供发布名称'
                  : updateInfo.releaseName,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (updateInfo.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.all(Constants.radius),
                ),
                child: Text(
                  updateInfo.releaseNotes,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: applying || !canApply ? null : onApply,
            icon: applying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_rounded),
            label: Text(
              applying
                  ? '正在启动更新...'
                  : canApply
                  ? '立即更新至 ${updateInfo.latestVersion}'
                  : hasError
                  ? '检查更新失败'
                  : '已是最新版本',
            ),
          ),
        ],
      ),
    );
  }

  String _title(ServerUpdateInfo? info, bool hasError) {
    if (hasError) return '检查更新失败';
    if (info == null) return '正在检查更新';
    return info.updateAvailable ? '发现服务端更新' : '服务端已是最新版本';
  }

  String _description(ServerUpdateInfo? info, bool hasError) {
    if (hasError) return '无法从所选更新渠道获取版本信息，请稍后重新检查。';
    if (info == null) return '正在从所选更新渠道获取版本信息。';
    return info.updateAvailable
        ? '确认后服务端会从 GitHub 下载并自动重启。'
        : '当前服务端版本已与所选渠道保持一致。';
  }
}

class _UpdateProgressStatus extends StatelessWidget {
  const _UpdateProgressStatus({this.status});

  final ServerUpdateStatusInfo? status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final message = status?.message;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.all(Constants.radius),
      ),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message == null || message.isEmpty ? '正在提交更新任务...' : message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value.isEmpty ? '未知' : value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: highlighted ? colors.primary : null,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
