import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/download_repository.dart';

enum DownloadFilter { downloading, completed }

class DownloadProgressController extends GetxController
    with WidgetsBindingObserver {
  DownloadProgressController({DownloadRepository? repository})
    : _repository = repository ?? DownloadRepository();

  final DownloadRepository _repository;
  final tasks = <DownloadTask>[].obs;
  final error = Rxn<Object>();
  final loading = true.obs;
  final filter = DownloadFilter.downloading.obs;
  final changingTaskState = <String>{}.obs;
  Timer? _timer;
  var _requesting = false;
  var _showingError = false;
  var _appIsResumed = true;
  var _isActive = false;

  List<DownloadTask> get filteredTasks => tasks
      .where(
        (task) => switch (filter.value) {
          DownloadFilter.downloading => !isCompleted(task),
          DownloadFilter.completed => isCompleted(task),
        },
      )
      .toList();

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    _syncPolling();
  }

  void setActive(bool value) {
    if (_isActive == value) return;
    _isActive = value;
    _syncPolling();
  }

  void setFilter(DownloadFilter value) {
    filter.value = value;
  }

  bool isCompleted(DownloadTask task) =>
      task.progress >= 1 ||
      const {
        'uploading',
        'stalledUP',
        'stoppedUP',
        'queuedUP',
        'checkingUP',
      }.contains(task.state);

  bool isPaused(DownloadTask task) => task.state == 'stoppedDL';

  Future<void> pause(DownloadTask task) async {
    await _changeTaskState(task, _repository.pauseTask);
  }

  Future<void> resume(DownloadTask task) async {
    await _changeTaskState(task, _repository.resumeTask);
  }

  Future<void> loadTasks() async {
    if (_requesting || isClosed) return;
    _requesting = true;
    try {
      final loadedTasks = await _repository.listTasks();
      if (isClosed) return;
      tasks.assignAll(loadedTasks);
      error.value = null;
      loading.value = false;
    } catch (caught) {
      if (isClosed) return;
      error.value = caught;
      loading.value = false;
      await _showErrorDialog(caught);
    } finally {
      _requesting = false;
    }
  }

  void _syncPolling() {
    if (_appIsResumed && _isActive) {
      _timer?.cancel();
      unawaited(loadTasks());
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => loadTasks());
      return;
    }
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _changeTaskState(
    DownloadTask task,
    Future<void> Function(String hash) action,
  ) async {
    if (isClosed) return;
    changingTaskState.add(task.hash);
    try {
      await action(task.hash);
      if (isClosed) return;
      await loadTasks();
    } catch (caught) {
      await _showErrorDialog(caught);
    } finally {
      if (!isClosed) changingTaskState.remove(task.hash);
    }
  }

  Future<void> _showErrorDialog(Object caught) async {
    if (_showingError || isClosed) return;
    _showingError = true;
    await showErrorDialog(
      title: '下载服务异常',
      message: errorMessageOf(caught),
      error: caught,
    );
    _showingError = false;
  }
}
