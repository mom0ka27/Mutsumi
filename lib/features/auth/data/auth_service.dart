import 'package:dio/dio.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/dio_client.dart';

class AuthService {
  AuthService(String serverUrl, {String? certificateSha256})
    : _dio = DioClient(serverUrl, certificateSha256: certificateSha256).dio;

  final Dio _dio;

  Future<LoginResult?> login({
    required String username,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      loginApiPath,
      data: FormData.fromMap({'username': username, 'password': password}),
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

class LoginResult {
  const LoginResult({required this.accessToken, required this.permissionGroup});

  final String accessToken;
  final String permissionGroup;
}
