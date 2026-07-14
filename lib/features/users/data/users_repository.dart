import '../../../core/network/api_paths.dart';
import '../../../core/network/dio_client.dart';
import '../../settings/data/settings_repository.dart';

class UsersRepository {
  UsersRepository({SettingsRepository? settingsRepository})
    : _settings = settingsRepository ?? SettingsRepository();

  final SettingsRepository _settings;
  DioClient? _cachedClient;
  String? _cachedUrl;
  String? _cachedToken;
  String? _cachedFingerprint;

  Future<List<ManagedUser>> listUsers() async {
    final response = await _client().dio.get<List<dynamic>>(usersApiPath);
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ManagedUser.fromJson)
        .toList();
  }

  Future<void> createUser({
    required String username,
    required String password,
    required String permissionGroup,
  }) async {
    await _client().dio.post<void>(
      usersApiPath,
      data: {
        'username': username,
        'password': password,
        'permission_group': permissionGroup,
      },
    );
  }

  Future<void> updateUser(
    int id, {
    required String username,
    required String permissionGroup,
    String? password,
  }) async {
    await _client().dio.patch<void>(
      '$usersApiPath/$id',
      data: {
        'username': username,
        'permission_group': permissionGroup,
        if (password != null && password.isNotEmpty) 'password': password,
      },
    );
  }

  Future<void> deleteUser(int id) =>
      _client().dio.delete<void>('$usersApiPath/$id');

  DioClient _client() {
    final url = _settings.getServerUrl();
    final token = _settings.getAccessToken(url);
    final fingerprint = _settings.getCertificateFingerprint(url);
    if (_cachedClient == null ||
        _cachedUrl != url ||
        _cachedToken != token ||
        _cachedFingerprint != fingerprint) {
      _cachedClient = DioClient(
        url,
        certificateSha256: fingerprint,
        accessToken: token,
      );
      _cachedUrl = url;
      _cachedToken = token;
      _cachedFingerprint = fingerprint;
    }
    return _cachedClient!;
  }
}

class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.username,
    required this.permissionGroup,
  });

  factory ManagedUser.fromJson(Map<String, dynamic> json) => ManagedUser(
    id: (json['id'] as num).toInt(),
    username: json['username'] as String? ?? '',
    permissionGroup: json['permission_group'] as String? ?? 'User',
  );

  final int id;
  final String username;
  final String permissionGroup;
}
