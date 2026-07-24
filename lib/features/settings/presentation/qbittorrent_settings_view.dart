import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/settings_repository.dart';
import '../data/authenticated_server_client.dart';

class QBittorrentSettingsView extends StatefulWidget {
  const QBittorrentSettingsView({super.key, this.bottomPadding = 120});

  final double bottomPadding;

  @override
  State<QBittorrentSettingsView> createState() =>
      _QBittorrentSettingsViewState();
}

class QBittorrentSettingsPage extends StatelessWidget {
  const QBittorrentSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          'qBittorrent',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
        centerTitle: false,
      ),
      body: const QBittorrentSettingsView(bottomPadding: 24),
    );
  }
}

class _QBittorrentSettingsViewState extends State<QBittorrentSettingsView> {
  final _settings = SettingsRepository();
  late final _client = AuthenticatedServerClient(settingsRepository: _settings);
  final _shareRatioSlider = 3.0.obs;
  Map<String, dynamic>? _config;
  final _loading = true.obs;
  final _saving = false.obs;
  final _forbidden = false.obs;
  final _errorMessage = RxnString();
  var _showingError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    _errorMessage.value = null;
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        qbittorrentConfigApiPath,
      );
      if (!mounted) return;
      _config = response.data;
      final ratio = ((response.data?['share_ratio_limit'] as num?) ?? 3.0)
          .toDouble();
      _shareRatioSlider.value = ratio < 0 ? 10 : ratio.clamp(0, 9.9);
      _forbidden.value = false;
    } on DioException catch (error) {
      if (error.response?.statusCode == 403) {
        _forbidden.value = true;
      } else {
        _errorMessage.value = errorMessageOf(error);
        await _showErrorDialog(error);
      }
    } catch (error) {
      _errorMessage.value = errorMessageOf(error);
      await _showErrorDialog(error);
    } finally {
      if (mounted) _loading.value = false;
    }
  }

  Future<void> _showErrorDialog(Object error) async {
    if (_showingError || !mounted) return;
    _showingError = true;
    await showErrorDialog(
      title: '加载设置失败',
      message: errorMessageOf(error),
      error: error,
    );
    _showingError = false;
  }

  Future<void> _save() async {
    if (_config == null) {
      return;
    }
    _saving.value = true;
    try {
      await _client.dio.put<void>(
        qbittorrentConfigApiPath,
        data: {
          'url': _config!['url'] ?? '',
          'username': _config!['username'] ?? '',
          'password': null,
          'download_path': _config!['download_path'] ?? '',
          'share_ratio_limit': _shareRatioSlider.value >= 10
              ? -1.0
              : _shareRatioSlider.value,
        },
      );
      if (mounted) {
        await showInfoDialog(title: '保存成功', message: '分享率限制已保存');
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 403) {
        _forbidden.value = true;
      } else {
        await showErrorDialog(
          title: '保存失败',
          message: errorMessageOf(error),
          error: error,
        );
      }
    } catch (error) {
      await showErrorDialog(
        title: '保存失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (mounted) _saving.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (_loading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_forbidden.value) {
        return _AccessDenied(bottomPadding: widget.bottomPadding);
      }
      if (_errorMessage.value != null) return const SizedBox.shrink();
      return ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          Constants.topPadding,
          20,
          widget.bottomPadding,
        ),
        children: [
          Text('下载设置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          GlassCard(
            useOwnLayer: true,
            padding: const EdgeInsets.all(16),
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            settings: AppGlassSettings.standard(context),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            '分享率限制',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          Text(
                            _ratioLabel,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _shareRatioSlider.value,
                        min: 0,
                        max: 10,
                        divisions: 100,
                        label: _ratioLabel,
                        onChanged: _saving.value
                            ? null
                            : (value) => _shareRatioSlider.value = value,
                      ),
                    ],
                  ),
                  const Text('新任务达到该分享率后，按 qBittorrent 的限额动作处理'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving.value ? null : _save,
            icon: _saving.value
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('保存'),
          ),
        ],
      );
    });
  }

  String get _ratioLabel => _shareRatioSlider.value >= 10
      ? '无限'
      : _shareRatioSlider.value.toStringAsFixed(1);
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(20, Constants.topPadding, 20, bottomPadding),
    children: [
      GlassCard(
        useOwnLayer: true,
        padding: const EdgeInsets.all(24),
        shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
        settings: AppGlassSettings.standard(context),
        child: const Column(
          children: [
            Icon(Icons.lock_outline_rounded, size: 48),
            SizedBox(height: 16),
            Text(
              '仅管理员可访问',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text('当前账户没有读取或修改 qBittorrent 设置的权限。', textAlign: TextAlign.center),
          ],
        ),
      ),
    ],
  );
}
