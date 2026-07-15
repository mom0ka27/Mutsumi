import '../../../core/network/api_paths.dart';
import 'authenticated_server_client.dart';

enum ServerUpdateChannel { release, prerelease, branch }

ServerUpdateChannel serverUpdateChannelOf(String? value) => switch (value) {
  'prerelease' => ServerUpdateChannel.prerelease,
  'branch' => ServerUpdateChannel.branch,
  _ => ServerUpdateChannel.release,
};

class ServerUpdateService {
  ServerUpdateService({AuthenticatedServerClient? client})
    : _client = client ?? AuthenticatedServerClient();

  final AuthenticatedServerClient _client;

  Future<ServerUpdateInfo> getUpdate(ServerUpdateChannel channel) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      updatesApiPath,
      queryParameters: {'channel': channel.name},
    );
    final data = response.data ?? {};
    return ServerUpdateInfo(
      channel: ServerUpdateChannel.values.byName(
        data['channel'] as String? ?? channel.name,
      ),
      currentVersion: data['current_version'] as String? ?? '',
      latestVersion: data['latest_version'] as String? ?? '',
      releaseName: data['release_name'] as String? ?? '',
      releaseNotes: data['release_notes'] as String? ?? '',
      updateAvailable: data['update_available'] == true,
    );
  }

  Future<ServerUpdateChannel> getUpdateChannel() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      updateChannelApiPath,
    );
    return serverUpdateChannelOf(response.data?['channel'] as String?);
  }

  Future<void> setUpdateChannel(ServerUpdateChannel channel) => _client.dio
      .put<void>(updateChannelApiPath, data: {'channel': channel.name});

  Future<void> applyUpdate(ServerUpdateChannel channel) =>
      _client.dio.post<void>(updatesApiPath, data: {'channel': channel.name});

  Future<ServerUpdateStatusInfo> getUpdateStatus() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      updateStatusApiPath,
    );
    final data = response.data ?? {};
    return ServerUpdateStatusInfo(
      status: serverUpdateStatusOf(data['status'] as String?),
      targetVersion: data['target_version'] as String? ?? '',
      message: data['message'] as String? ?? '',
    );
  }
}

class ServerUpdateInfo {
  const ServerUpdateInfo({
    required this.channel,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseNotes,
    required this.updateAvailable,
  });

  final ServerUpdateChannel channel;
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseNotes;
  final bool updateAvailable;
}

enum ServerUpdateStatus { downloading, installing, running, failed }

ServerUpdateStatus serverUpdateStatusOf(String? value) => switch (value) {
  'downloading' => ServerUpdateStatus.downloading,
  'installing' => ServerUpdateStatus.installing,
  'running' => ServerUpdateStatus.running,
  'failed' => ServerUpdateStatus.failed,
  _ => ServerUpdateStatus.running,
};

class ServerUpdateStatusInfo {
  const ServerUpdateStatusInfo({
    required this.status,
    required this.targetVersion,
    required this.message,
  });

  final ServerUpdateStatus status;
  final String targetVersion;
  final String message;
}
