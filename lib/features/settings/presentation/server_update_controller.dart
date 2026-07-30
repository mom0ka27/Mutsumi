import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/server_update_service.dart';

class ServerUpdateController extends GetxController {
  ServerUpdateController({ServerUpdateService? service})
    : _service = service ?? ServerUpdateService();

  final ServerUpdateService _service;
  final channel = ServerUpdateChannel.release.obs;
  final info = Rxn<ServerUpdateInfo>();
  final errorMessage = RxnString();
  final loading = true.obs;
  final applying = false.obs;
  final updateStatus = Rxn<ServerUpdateStatusInfo>();
  Timer? _statusTimer;
  var _statusChecks = 0;
  var _targetVersion = '';

  @override
  void onInit() {
    super.onInit();
    loadChannel();
  }

  @override
  void onClose() {
    _statusTimer?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    if (loading.value && info.value != null) return;
    loading.value = true;
    errorMessage.value = null;
    try {
      final loadedInfo = await _service.getUpdate(channel.value);
      if (isClosed) return;
      info.value = loadedInfo;
    } catch (error) {
      if (isClosed) return;
      errorMessage.value = errorMessageOf(error);
    } finally {
      if (!isClosed) loading.value = false;
    }
  }

  Future<void> loadChannel() async {
    try {
      final loadedChannel = await _service.getUpdateChannel();
      if (isClosed) return;
      channel.value = loadedChannel;
    } catch (error, stackTrace) {
      AppLogger.error(
        '读取服务端更新渠道失败，使用 Release 渠道',
        tag: 'ServerUpdate',
        error: error,
        stackTrace: stackTrace,
      );
      if (isClosed) return;
      channel.value = ServerUpdateChannel.release;
    }
    if (!isClosed) unawaited(load());
  }

  Future<void> apply() async {
    final currentInfo = info.value;
    if (currentInfo == null || !currentInfo.updateAvailable) return;
    final confirmed = await showAppDialog<bool>(
      AlertDialog(
        title: const Text('确认更新服务端'),
        content: Text('将更新至 ${currentInfo.latestVersion}，服务会短暂重启。'),
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
    if (confirmed != true || isClosed) return;
    applying.value = true;
    _targetVersion = currentInfo.latestVersion;
    updateStatus.value = null;
    try {
      await _service.applyUpdate(channel.value);
      if (isClosed) return;
      _startStatusPolling();
    } catch (error) {
      if (!isClosed) {
        await showErrorDialog(
          title: '更新失败',
          message: errorMessageOf(error),
          error: error,
        );
        applying.value = false;
      }
    }
  }

  Future<void> changeChannel(ServerUpdateChannel value) async {
    if (channel.value == value) return;
    final previousChannel = channel.value;
    channel.value = value;
    info.value = null;
    try {
      await _service.setUpdateChannel(value);
    } catch (error) {
      if (!isClosed) {
        channel.value = previousChannel;
        errorMessage.value = errorMessageOf(error);
      }
      return;
    }
    unawaited(load());
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusChecks = 0;
    unawaited(_pollUpdateStatus());
    _statusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollUpdateStatus(),
    );
  }

  Future<void> _pollUpdateStatus() async {
    if (isClosed || !applying.value) return;
    _statusChecks++;
    if (_statusChecks > 120) {
      _statusTimer?.cancel();
      applying.value = false;
      errorMessage.value = '等待服务端重启超时，请稍后手动刷新。';
      return;
    }
    try {
      final status = await _service.getUpdateStatus();
      if (isClosed) return;
      updateStatus.value = status;
      if (status.status == ServerUpdateStatus.running) {
        if (await _confirmUpdatedVersion()) _statusTimer?.cancel();
      } else if (status.status == ServerUpdateStatus.failed) {
        _statusTimer?.cancel();
        applying.value = false;
        errorMessage.value = status.message.isEmpty
            ? '服务端更新失败。'
            : status.message;
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        '查询服务端更新状态失败',
        tag: 'ServerUpdate',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _confirmUpdatedVersion() async {
    try {
      final currentInfo = await _service.getUpdate(channel.value);
      if (isClosed) return false;
      if (_versionsEqual(currentInfo.currentVersion, _targetVersion)) {
        applying.value = false;
        info.value = currentInfo;
        return true;
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        '确认服务端版本失败',
        tag: 'ServerUpdate',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return false;
  }

  bool _versionsEqual(String left, String right) =>
      left.replaceFirst(RegExp(r'^v'), '') ==
      right.replaceFirst(RegExp(r'^v'), '');
}
