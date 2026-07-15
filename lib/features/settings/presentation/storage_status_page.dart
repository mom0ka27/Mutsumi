import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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

class StorageStatusPage extends StatefulWidget {
  const StorageStatusPage({super.key});

  @override
  State<StorageStatusPage> createState() => _StorageStatusPageState();
}

class _StorageStatusPageState extends State<StorageStatusPage> {
  final _settings = SettingsRepository();
  late final _client = AuthenticatedServerClient(settingsRepository: _settings);
  final _loading = true.obs;
  final _forbidden = false.obs;
  final _errorMessage = RxnString();
  StorageStatus? _status;
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
        storageApiPath,
      );
      if (!mounted || response.data == null) return;
      setState(() => _status = StorageStatus.fromJson(response.data!));
      _forbidden.value = false;
    } on DioException catch (error) {
      if (error.response?.statusCode == 403) {
        _forbidden.value = true;
      } else {
        _errorMessage.value = errorMessageOf(error);
        await _showErrorDialog(_errorMessage.value!);
      }
    } catch (error) {
      _errorMessage.value = errorMessageOf(error);
      await _showErrorDialog(_errorMessage.value!);
    } finally {
      if (mounted) _loading.value = false;
    }
  }

  Future<void> _showErrorDialog(String message) async {
    if (_showingError || !mounted) return;
    _showingError = true;
    await showErrorDialog(title: '加载存储信息失败', message: message);
    _showingError = false;
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
            onTap: _load,
          ),
        ],
        centerTitle: false,
      ),
      body: Obx(() {
        if (_loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_forbidden.value) {
          return const _AccessDenied();
        }
        final status = _status;
        if (status == null) {
          return const SizedBox.shrink();
        }
        return ListView(
          padding: EdgeInsets.fromLTRB(20, Constants.topPadding, 20, 24),
          children: [
            Text('服务器存储', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(status.dataPath, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            _SummaryCard(status: status),
            const SizedBox(height: 20),
            Text('详情', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (status.anime.isEmpty)
              const _EmptyCard()
            else
              GlassCard(
                useOwnLayer: true,
                padding: EdgeInsets.zero,
                shape: LiquidRoundedSuperellipse(
                  borderRadius: Constants.radius.x,
                ),
                settings: AppGlassSettings.standard(context),
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < status.anime.length;
                      index++
                    ) ...[
                      _AnimeStorageTile(anime: status.anime[index]),
                      if (index < status.anime.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.status});

  final StorageStatus status;

  @override
  Widget build(BuildContext context) {
    final diskUsagePercent = status.diskUsedBytes / status.diskTotalBytes * 100;
    return GlassCard(
      useOwnLayer: true,
      padding: const EdgeInsets.all(20),
      shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
      settings: AppGlassSettings.standard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatBytes(status.dataSizeBytes)} · ${status.dataFileCount} 个文件',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '剩余容量',
                  value: formatBytes(status.diskFreeBytes),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '已用容量',
                  value: formatBytes(status.diskUsedBytes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: diskUsagePercent / 100),
          const SizedBox(height: 8),
          Text(
            '磁盘已使用 ${diskUsagePercent.toStringAsFixed(1)}% · 总容量 ${formatBytes(status.diskTotalBytes)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class _AnimeStorageTile extends StatelessWidget {
  const _AnimeStorageTile({required this.anime});

  final AnimeStorage anime;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.folder_rounded),
    title: Text(anime.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      anime.downloadHash ?? '尚未创建下载文件夹',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Text(formatBytes(anime.sizeBytes)),
  );
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(20, Constants.topPadding, 20, 24),
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
            Text('当前账户没有查看服务器存储信息的权限。', textAlign: TextAlign.center),
          ],
        ),
      ),
    ],
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) => GlassCard(
    useOwnLayer: true,
    padding: const EdgeInsets.all(24),
    shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
    settings: AppGlassSettings.standard(context),
    child: const Center(child: Text('无 Anime')),
  );
}

class StorageStatus {
  const StorageStatus({
    required this.dataPath,
    required this.dataSizeBytes,
    required this.dataFileCount,
    required this.diskTotalBytes,
    required this.diskUsedBytes,
    required this.diskFreeBytes,
    required this.anime,
  });

  factory StorageStatus.fromJson(Map<String, dynamic> json) => StorageStatus(
    dataPath: json['data_path'] as String? ?? '',
    dataSizeBytes: (json['data_size_bytes'] as num?)?.toInt() ?? 0,
    dataFileCount: (json['data_file_count'] as num?)?.toInt() ?? 0,
    diskTotalBytes: (json['disk_total_bytes'] as num?)?.toInt() ?? 0,
    diskUsedBytes: (json['disk_used_bytes'] as num?)?.toInt() ?? 0,
    diskFreeBytes: (json['disk_free_bytes'] as num?)?.toInt() ?? 0,
    anime: (json['anime'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AnimeStorage.fromJson)
        .toList(),
  );

  final String dataPath;
  final int dataSizeBytes;
  final int dataFileCount;
  final int diskTotalBytes;
  final int diskUsedBytes;
  final int diskFreeBytes;
  final List<AnimeStorage> anime;
}

class AnimeStorage {
  const AnimeStorage({
    required this.name,
    required this.sizeBytes,
    required this.fileCount,
    required this.downloadHash,
  });

  factory AnimeStorage.fromJson(Map<String, dynamic> json) => AnimeStorage(
    name: json['name'] as String? ?? '',
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
    downloadHash: json['download_hash'] as String?,
  );

  final String name;
  final int sizeBytes;
  final int fileCount;
  final String? downloadHash;
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
}
