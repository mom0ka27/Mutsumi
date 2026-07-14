import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import 'settings_repository.dart';

class AuthenticatedServerClient {
  AuthenticatedServerClient({SettingsRepository? settingsRepository})
    : _settings = settingsRepository ?? SettingsRepository();

  final SettingsRepository _settings;
  DioClient? _cachedClient;
  String? _cachedUrl;
  String? _cachedToken;
  String? _cachedFingerprint;

  Dio get dio {
    final url = _settings.getServerUrl();
    final token = _settings.getAccessToken(url);
    if (url.isEmpty || token == null || token.isEmpty) {
      throw StateError('请先连接并登录服务器');
    }
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
    return _cachedClient!.dio;
  }
}
