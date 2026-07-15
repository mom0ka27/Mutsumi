import '../../../core/network/api_paths.dart';
import 'authenticated_server_client.dart';

enum ServerUpdateChannel { release, prerelease, branch }

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
      integrityVerified: data['integrity_verified'] == true,
    );
  }

  Future<void> applyUpdate(ServerUpdateChannel channel) =>
      _client.dio.post<void>(updatesApiPath, data: {'channel': channel.name});
}

class ServerUpdateInfo {
  const ServerUpdateInfo({
    required this.channel,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseNotes,
    required this.updateAvailable,
    required this.integrityVerified,
  });

  final ServerUpdateChannel channel;
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseNotes;
  final bool updateAvailable;
  final bool integrityVerified;
}
