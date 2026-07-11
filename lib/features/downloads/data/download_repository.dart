import '../../../core/network/api_paths.dart';
import '../../../core/network/dio_client.dart';
import '../../settings/data/settings_repository.dart';

class DownloadRepository {
  DownloadRepository({SettingsRepository? settingsRepository})
    : _settingsRepository = settingsRepository ?? SettingsRepository();

  final SettingsRepository _settingsRepository;

  Future<List<DownloadTask>> listTasks() async {
    final response = await _dio().dio.get<dynamic>(
      '$qbittorrentApiPath/torrents',
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException('下载任务数据格式错误');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(DownloadTask.fromJson)
        .toList();
  }

  Future<void> pauseTask(String hash) async {
    await _dio().dio.post<void>('$qbittorrentApiPath/torrents/$hash/pause');
  }

  DioClient _dio() {
    final serverUrl = _settingsRepository.getServerUrl();
    final token = _settingsRepository.getAccessToken(serverUrl);
    if (serverUrl.isEmpty || token == null || token.isEmpty) {
      throw StateError('请先连接并登录服务器');
    }
    return DioClient(
      serverUrl,
      certificateSha256: _settingsRepository.getCertificateFingerprint(
        serverUrl,
      ),
      accessToken: token,
    );
  }
}

class DownloadTask {
  const DownloadTask({
    required this.hash,
    required this.name,
    required this.state,
    required this.progress,
    required this.totalSize,
    required this.downloaded,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.eta,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    hash: json['hash'] as String? ?? '',
    name: json['name'] as String? ?? '',
    state: json['state'] as String? ?? 'unknown',
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    totalSize: (json['total_size'] as num?)?.toInt() ?? 0,
    downloaded: (json['downloaded'] as num?)?.toInt() ?? 0,
    downloadSpeed: (json['dlspeed'] as num?)?.toInt() ?? 0,
    uploadSpeed: (json['upspeed'] as num?)?.toInt() ?? 0,
    eta: (json['eta'] as num?)?.toInt() ?? 0,
  );

  final String hash;
  final String name;
  final String state;
  final double progress;
  final int totalSize;
  final int downloaded;
  final int downloadSpeed;
  final int uploadSpeed;
  final int eta;
}
