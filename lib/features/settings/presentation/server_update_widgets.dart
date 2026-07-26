import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_glass_settings.dart';
import '../data/server_update_service.dart';

/// Presentation pieces of the server update page, split out to keep
/// `server_update_page.dart` focused on loading and applying updates.

class UpdateInfoCard extends StatelessWidget {
  const UpdateInfoCard({
    super.key,
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
          VersionRow(
            label: '当前版本',
            value: hasError ? '检查失败' : updateInfo?.currentVersion ?? '检查中...',
          ),
          const SizedBox(height: 12),
          VersionRow(
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
            UpdateProgressStatus(status: updateStatus),
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
          FilledButton(
            onPressed: applying || !canApply ? null : onApply,
            child: Text(
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

class UpdateProgressStatus extends StatelessWidget {
  const UpdateProgressStatus({super.key, this.status});

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

class VersionRow extends StatelessWidget {
  const VersionRow({
    super.key,
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
