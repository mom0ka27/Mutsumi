import 'package:dio/dio.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_service.dart';

class SetupService {
  SetupService(String serverUrl, {String? certificateSha256})
    : _dio = DioClient(serverUrl, certificateSha256: certificateSha256).dio;

  final Dio _dio;

  Future<SetupStatus> getStatus() async {
    final response = await _dio.get<Map<String, dynamic>>(setupApiPath);
    final data = response.data ?? {};
    return SetupStatus(
      initialized: data['initialized'] == true,
      serverName: data['server_name'] as String? ?? '',
    );
  }

  Future<bool> isInitialized() async {
    final status = await getStatus();
    return status.initialized;
  }

  Future<LoginResult?> initialize({
    required String username,
    required String password,
    String? serverName,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      setupApiPath,
      data: {
        'username': username,
        'password': password,
        if (serverName != null && serverName.trim().isNotEmpty)
          'server_name': serverName.trim(),
      },
    );
    final data = response.data;
    final accessToken = data?['access_token'] as String?;
    final permissionGroup = data?['permission_group'] as String?;
    if (accessToken == null || permissionGroup == null) {
      return null;
    }
    return LoginResult(
      accessToken: accessToken,
      permissionGroup: permissionGroup,
    );
  }
}

class SetupStatus {
  const SetupStatus({required this.initialized, required this.serverName});

  final bool initialized;
  final String serverName;
}
