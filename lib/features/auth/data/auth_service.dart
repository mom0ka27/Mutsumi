import 'package:dio/dio.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/dio_client.dart';

class AuthService {
  AuthService(String serverUrl, {String? certificateSha256})
    : _dio = DioClient(serverUrl, certificateSha256: certificateSha256).dio;

  final Dio _dio;

  Future<String?> login({
    required String username,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      loginApiPath,
      data: FormData.fromMap({'username': username, 'password': password}),
    );
    return response.data?['access_token'] as String?;
  }
}
