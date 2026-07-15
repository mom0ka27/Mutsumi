import 'package:flutter/material.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_dialog.dart';
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
  var _loading = true;
  var _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _info = null;
    });
    try {
      final info = await _service.getUpdate(_channel);
      if (mounted) setState(() => _info = info);
    } catch (error) {
      if (mounted) {
        await showErrorDialog(title: '检查更新失败', message: errorMessageOf(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final info = _info;
    if (info == null || !info.updateAvailable) return;
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('服务端更新')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SegmentedButton<ServerUpdateChannel>(
                segments: const [
                  ButtonSegment(
                    value: ServerUpdateChannel.release,
                    label: Text('Release'),
                  ),
                  ButtonSegment(
                    value: ServerUpdateChannel.prerelease,
                    label: Text('Pre-release'),
                  ),
                  ButtonSegment(
                    value: ServerUpdateChannel.branch,
                    label: Text('main'),
                  ),
                ],
                selected: {_channel},
                onSelectionChanged: (value) {
                  setState(() => _channel = value.first);
                  _load();
                },
              ),
              const SizedBox(height: 24),
              if (_info != null) ...[
                Text('当前版本：${_info!.currentVersion}'),
                Text('最新版本：${_info!.latestVersion}'),
                const SizedBox(height: 12),
                Text(
                  _info!.releaseName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_info!.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_info!.releaseNotes),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _applying || !_info!.updateAvailable
                      ? null
                      : _apply,
                  child: Text(
                    _applying
                        ? '更新中...'
                        : _info!.updateAvailable
                        ? '立即更新'
                        : '已是最新版本',
                  ),
                ),
              ],
            ],
          ),
  );
}
