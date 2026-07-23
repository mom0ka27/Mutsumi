import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/app_glass_settings.dart';

import '../data/download_repository.dart';

class DownloadProgressView extends StatefulWidget {
  const DownloadProgressView({super.key, required this.isActive});

  final bool isActive;

  @override
  State<DownloadProgressView> createState() => _DownloadProgressViewState();
}

class _DownloadProgressViewState extends State<DownloadProgressView>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final _repository = DownloadRepository();
  Timer? _timer;
  final _tasks = <DownloadTask>[].obs;
  final _error = Rxn<Object>();
  final _loading = true.obs;
  bool _requesting = false;
  bool _showingError = false;
  bool _appIsResumed = true;
  final _filter = _DownloadFilter.downloading.obs;
  final _changingTaskState = <String>{}.obs;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncPolling();
  }

  @override
  void didUpdateWidget(covariant DownloadProgressView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    _syncPolling();
  }

  void _syncPolling() {
    if (_appIsResumed && widget.isActive) {
      _startPolling();
      return;
    }
    _timer?.cancel();
    _timer = null;
  }

  void _startPolling() {
    _timer?.cancel();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_requesting) {
      return;
    }
    _requesting = true;
    try {
      final tasks = await _repository.listTasks();
      if (mounted) {
        _tasks.assignAll(tasks);
        _error.value = null;
        _loading.value = false;
      }
    } catch (error) {
      if (mounted) {
        _error.value = error;
        _loading.value = false;
      }
      await _showErrorDialog(error);
    } finally {
      _requesting = false;
    }
  }

  Future<void> _showErrorDialog(Object error) async {
    if (_showingError || !mounted) {
      return;
    }
    _showingError = true;
    await showErrorDialog(
      title: '下载服务异常',
      message: errorMessageOf(error),
      error: error,
    );
    _showingError = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(() {
      if (_loading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      final tasks = _tasks
          .where(
            (task) => switch (_filter.value) {
              _DownloadFilter.downloading => !_isCompleted(task),
              _DownloadFilter.completed => _isCompleted(task),
            },
          )
          .toList();
      return ListView.separated(
        padding: EdgeInsets.fromLTRB(
          20,
          Constants.topPadding,
          20,
          Constants.bottomPadding,
        ),
        itemCount: tasks.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return SegmentedButton<_DownloadFilter>(
              segments: const [
                ButtonSegment(
                  value: _DownloadFilter.downloading,
                  label: Text('下载中'),
                  icon: Icon(Icons.downloading_rounded),
                ),
                ButtonSegment(
                  value: _DownloadFilter.completed,
                  label: Text('已完成'),
                  icon: Icon(Icons.check_circle_outline_rounded),
                ),
              ],
              selected: {_filter.value},
              onSelectionChanged: (value) => _filter.value = value.first,
            );
          }
          final task = tasks[index - 1];
          return _DownloadCard(
            task: task,
            changingTaskState: _changingTaskState.contains(task.hash),
            onTaskAction: _isCompleted(task)
                ? null
                : _isPaused(task)
                ? () => _resume(task)
                : () => _pause(task),
            taskAction: _isPaused(task)
                ? _DownloadTaskAction.resume
                : _DownloadTaskAction.pause,
          );
        },
      );
    });
  }

  bool _isCompleted(DownloadTask task) =>
      task.progress >= 1 ||
      const {
        'uploading',
        'stalledUP',
        'stoppedUP',
        'queuedUP',
        'checkingUP',
      }.contains(task.state);

  bool _isPaused(DownloadTask task) => task.state == 'stoppedDL';

  Future<void> _pause(DownloadTask task) async {
    await _changeTaskState(task, _repository.pauseTask);
  }

  Future<void> _resume(DownloadTask task) async {
    await _changeTaskState(task, _repository.resumeTask);
  }

  Future<void> _changeTaskState(
    DownloadTask task,
    Future<void> Function(String hash) action,
  ) async {
    _changingTaskState.add(task.hash);
    try {
      await action(task.hash);
      await _refresh();
    } catch (error) {
      await _showErrorDialog(error);
    } finally {
      if (mounted) _changingTaskState.remove(task.hash);
    }
  }
}

enum _DownloadFilter { downloading, completed }

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
