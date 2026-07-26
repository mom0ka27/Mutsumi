import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../logging/app_logger.dart';
import 'app_network_error.dart';

/// Reads the token to send with each request, so a refreshed token is picked up
/// without rebuilding the [Dio] instance (and losing its connection pool).
typedef AccessTokenProvider = String? Function();

/// Obtains a fresh access token after a 401. Returns `null` when the session
/// cannot be recovered, in which case the original error is surfaced.
typedef AccessTokenRefresher = Future<String?> Function();

const _retriedFlag = 'mutsumi.retried_after_refresh';

class DioClient {
  DioClient(
    String baseUrl, {
    String? certificateSha256,
    String? accessToken,
    AccessTokenProvider? accessTokenProvider,
    AccessTokenRefresher? refreshAccessToken,
  }) : _accessTokenProvider = accessTokenProvider ?? (() => accessToken),
       // Named parameters cannot be private, so this cannot be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _refreshAccessToken = refreshAccessToken,
       dio = Dio(
         BaseOptions(
           baseUrl: _normalizeBaseUrl(baseUrl),
           connectTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 10),
         ),
       ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _accessTokenProvider();
          if (token != null &&
              token.isNotEmpty &&
              !options.headers.containsKey('Authorization')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
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
          handler.next(response);
        },
        onError: (error, handler) async {
          AppLogger.error(
            '${error.response?.statusCode ?? 'ERR'} ${error.requestOptions.method} ${error.requestOptions.path}',
            tag: 'HTTP',
            error: error,
          );

          final retried = await _retryAfterRefresh(error);
          if (retried != null) {
            handler.resolve(retried);
            return;
          }
          handler.next(_withBusinessError(error));
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
  final AccessTokenProvider _accessTokenProvider;
  final AccessTokenRefresher? _refreshAccessToken;

  /// Re-authenticates once per request and replays it. Returns `null` when the
  /// error is not a recoverable 401 or the refresh failed.
  Future<Response<dynamic>?> _retryAfterRefresh(DioException error) async {
    final refresh = _refreshAccessToken;
    if (refresh == null ||
        error.response?.statusCode != 401 ||
        error.requestOptions.extra[_retriedFlag] == true) {
      return null;
    }

    final String? token;
    try {
      token = await refresh();
    } catch (refreshError, stackTrace) {
      AppLogger.error(
        '刷新登录状态失败',
        tag: 'HTTP',
        error: refreshError,
        stackTrace: stackTrace,
      );
      return null;
    }
    if (token == null || token.isEmpty) {
      return null;
    }

    final options = error.requestOptions
      ..extra[_retriedFlag] = true
      ..headers['Authorization'] = 'Bearer $token';
    try {
      // `fetch` bypasses the interceptor chain, so this cannot loop.
      return await dio.fetch<dynamic>(options);
    } catch (retryError, stackTrace) {
      AppLogger.error(
        '重放请求失败 ${options.method} ${options.path}',
        tag: 'HTTP',
        error: retryError,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Server business errors arrive as `{"detail": ..., "code": ...}` alongside a
  /// 4xx/5xx status; lift the code out so callers can branch on it.
  static DioException _withBusinessError(DioException error) {
    if (error.error is ApiBusinessException) return error;
    final data = error.response?.data;
    if (data is! Map || data['code'] is! int) return error;
    return error.copyWith(
      error: ApiBusinessException(
        data['code'] as int,
        data['detail'] as String? ?? '请求失败',
      ),
    );
  }

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
