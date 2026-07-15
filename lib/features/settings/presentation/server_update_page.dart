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

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _apply() async {
    final info = _info;
    if (info == null || !info.updateAvailable || !info.integrityVerified) {
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
    setState(() => _applying = true);
    try {
      await _service.applyUpdate(_channel);
      if (mounted) {
        await showInfoDialog(title: '更新已开始', message: '服务端正在下载、校验并重启，请稍后重新连接。');
      }
    } catch (error) {
      if (mounted) {
        await showErrorDialog(title: '更新失败', message: errorMessageOf(error));
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _changeChannel(ServerUpdateChannel channel) {
    if (_channel == channel) return;
    setState(() {
      _channel = channel;
      _info = null;
    });
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
    if (_loading && _info == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _info == null) {
      return _UpdateErrorState(message: _errorMessage!, onRetry: _load);
    }
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, Constants.topPadding, 20, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _UpdateInfoCard(
            channel: _channel,
            info: info,
            loading: _loading,
            applying: _applying,
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
    required this.loading,
    required this.applying,
    required this.onChannelChanged,
    required this.onApply,
  });

  final ServerUpdateChannel channel;
  final ServerUpdateInfo info;
  final bool loading;
  final bool applying;
  final ValueChanged<ServerUpdateChannel> onChannelChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canApply = info.updateAvailable && info.integrityVerified;
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
            backgroundColor: info.updateAvailable
                ? colors.primaryContainer
                : colors.secondaryContainer,
            foregroundColor: info.updateAvailable
                ? colors.onPrimaryContainer
                : colors.onSecondaryContainer,
            child: Icon(
              info.updateAvailable
                  ? Icons.system_update_rounded
                  : Icons.verified_rounded,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            info.updateAvailable ? '发现服务端更新' : '服务端已是最新版本',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            info.updateAvailable
                ? '选择更新来源，确认后服务端会下载、校验并自动重启。'
                : '当前服务端版本已与所选来源保持一致。',
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
                label: Text('Pre-release'),
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
          _VersionRow(label: '当前版本', value: info.currentVersion),
          const SizedBox(height: 12),
          _VersionRow(
            label: '可用版本',
            value: info.latestVersion,
            highlighted: info.updateAvailable,
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          Text('发布信息', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            info.releaseName.isEmpty ? '未提供发布名称' : info.releaseName,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.all(Constants.radius),
              ),
              child: Text(
                info.releaseNotes,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _IntegrityStatus(verified: info.integrityVerified),
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
                  ? '立即更新至 ${info.latestVersion}'
                  : info.integrityVerified
                  ? '已是最新版本'
                  : '更新包未通过校验',
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

class _IntegrityStatus extends StatelessWidget {
  const _IntegrityStatus({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = verified ? colors.primary : colors.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          verified ? Icons.verified_user_outlined : Icons.warning_amber_rounded,
          color: color,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                verified ? '更新包可校验' : '更新包无法校验',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Text(
                verified
                    ? '安装前将验证发布包的 SHA-256 摘要。'
                    : '当前来源没有可用的 SHA-256 校验文件，不能直接安装。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpdateErrorState extends StatelessWidget {
  const _UpdateErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, Constants.topPadding, 20, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: GlassCard(
            useOwnLayer: true,
            padding: const EdgeInsets.all(28),
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            settings: AppGlassSettings.standard(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: colors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  '无法检查更新',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新检查'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
