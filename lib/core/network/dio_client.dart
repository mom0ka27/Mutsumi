import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../logging/app_logger.dart';
import 'app_network_error.dart';

class DioClient {
  DioClient(String baseUrl, {String? certificateSha256, String? accessToken})
    : dio = Dio(
        BaseOptions(
          baseUrl: _normalizeBaseUrl(baseUrl),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 10),
          headers: accessToken == null || accessToken.isEmpty
              ? null
              : {'Authorization': 'Bearer $accessToken'},
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          AppLogger.info(
            '${options.method} ${options.baseUrl}${options.path}',
            tag: 'HTTP',
          );
          handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.info(
            '${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.path}',
            tag: 'HTTP',
          );
          final data = response.data;
          if (data is Map && data['code'] is int && data['code'] != 0) {
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                error: ApiBusinessException(
                  data['code'] as int,
                  data['msg'] as String? ?? '请求失败',
                ),
              ),
            );
            return;
          }
          handler.next(response);
        },
        onError: (error, handler) {
          AppLogger.error(
            '${error.response?.statusCode ?? 'ERR'} ${error.requestOptions.method} ${error.requestOptions.path}',
            tag: 'HTTP',
            error: error,
          );
          handler.next(error);
        },
      ),
    );

    final normalizedFingerprint = _normalizeFingerprint(
      certificateSha256 ?? '',
    );
    if (normalizedFingerprint.isNotEmpty) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) {
            final digest = sha256.convert(cert.der).toString();
            return digest == normalizedFingerprint;
          };
          return client;
        },
      );
    }
  }

  final Dio dio;

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String _normalizeFingerprint(String value) {
    return value.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toLowerCase();
  }
}
