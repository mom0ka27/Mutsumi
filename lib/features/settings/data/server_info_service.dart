import 'package:dio/dio.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/dio_client.dart';

class ServerInfoService {
  ServerInfoService(String serverUrl, {String? certificateSha256})
    : _dio = DioClient(serverUrl, certificateSha256: certificateSha256).dio;

  final Dio _dio;

  Future<ServerInfo> getInfo() async {
    final response = await _dio.get<Map<String, dynamic>>(healthApiPath);
    final data = response.data ?? {};
    return ServerInfo(
      version: data['server_version'] as String? ?? '',
      apiVersion: data['api_version'] as String? ?? '',
    );
  }
}

class ServerInfo {
  const ServerInfo({required this.version, required this.apiVersion});

  final String version;
  final String apiVersion;
}
