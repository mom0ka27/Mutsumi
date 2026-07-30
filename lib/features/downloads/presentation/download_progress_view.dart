import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_glass_settings.dart';
import '../../../core/extensions/build_context.dart';

import '../data/download_repository.dart';
import 'download_progress_controller.dart';

class DownloadProgressView extends GetView<DownloadProgressController> {
  const DownloadProgressView({super.key, required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    controller.setActive(isActive);
    return Obx(() {
      if (controller.loading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      final tasks = controller.filteredTasks;
      return ListView.separated(
        padding: context.homeContentPadding(),
        itemCount: tasks.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return SegmentedButton<DownloadFilter>(
              segments: const [
                ButtonSegment(
                  value: DownloadFilter.downloading,
                  label: Text('下载中'),
                  icon: Icon(Icons.downloading_rounded),
                ),
                ButtonSegment(
                  value: DownloadFilter.completed,
                  label: Text('已完成'),
                  icon: Icon(Icons.check_circle_outline_rounded),
                ),
              ],
              selected: {controller.filter.value},
              onSelectionChanged: (value) => controller.setFilter(value.first),
            );
          }
          final task = tasks[index - 1];
          return _DownloadCard(
            task: task,
            changingTaskState: controller.changingTaskState.contains(task.hash),
            onTaskAction: controller.isCompleted(task)
                ? null
                : controller.isPaused(task)
                ? () => controller.resume(task)
                : () => controller.pause(task),
            taskAction: controller.isPaused(task)
                ? _DownloadTaskAction.resume
                : _DownloadTaskAction.pause,
          );
        },
      );
    });
  }
}

enum _DownloadTaskAction { pause, resume }

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.task,
    required this.changingTaskState,
    required this.onTaskAction,
    required this.taskAction,
  });
  final DownloadTask task;
  final bool changingTaskState;
  final VoidCallback? onTaskAction;
  final _DownloadTaskAction taskAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = task.progress.clamp(0.0, 1.0);
    return GlassCard(
      useOwnLayer: true,
      shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
      settings: AppGlassSettings.standard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('${(progress * 100).toStringAsFixed(1)}%'),
              const Spacer(),
              Text(
                '${_bytes(task.downloadSpeed)}/s',
                style: TextStyle(color: colors.primary),
              ),
              if (onTaskAction != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: taskAction == _DownloadTaskAction.pause
                      ? '暂停'
                      : '继续下载',
                  onPressed: changingTaskState ? null : onTaskAction,
                  icon: changingTaskState
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          taskAction == _DownloadTaskAction.pause
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_state(task.state)} · ${_bytes(task.downloaded)} / ${_bytes(task.totalSize)} · 剩余 ${_eta(task.eta)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _state(String value) => switch (value) {
    'downloading' => '下载中',
    'stalledDL' => '等待数据',
    'pausedDL' => '已暂停',
    'queuedDL' => '排队中',
    'checkingDL' => '校验中',
    'error' => '错误',
    'uploading' || 'stalledUP' || 'pausedUP' => '已完成',
    _ => value,
  };

  String _bytes(int value) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = value.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _eta(int seconds) {
    if (seconds <= 0 || seconds >= 8640000) {
      return '--';
    }
    final duration = Duration(seconds: seconds);
    if (duration.inHours > 0) {
      return '${duration.inHours}小时${duration.inMinutes.remainder(60)}分';
    }
    return '${duration.inMinutes}分${duration.inSeconds.remainder(60)}秒';
  }
}
