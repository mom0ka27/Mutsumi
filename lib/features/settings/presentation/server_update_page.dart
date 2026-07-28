import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../../core/extensions/build_context.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/server_update_service.dart';
import 'server_update_widgets.dart';

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
    } catch (error, stackTrace) {
      AppLogger.error(
        '读取服务端更新渠道失败，使用 Release 渠道',
        tag: 'ServerUpdate',
        error: error,
        stackTrace: stackTrace,
      );
      _channel = ServerUpdateChannel.release;
    }
    if (mounted) unawaited(_load());
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
        await showErrorDialog(
          title: '更新失败',
          message: errorMessageOf(error),
          error: error,
        );
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
      final info = await _service.getUpdate(_channel);
      if (!mounted) return false;
      if (_versionsEqual(info.currentVersion, _targetVersion)) {
        setState(() {
          _applying = false;
          _info = info;
        });
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
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      topEdgeFade: true,
      bottomEdgeFade: false,
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
        padding: context.pageContentPadding(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: UpdateInfoCard(
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
