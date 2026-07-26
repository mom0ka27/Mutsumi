import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../../auth/data/token_refresher.dart';
import 'settings_repository.dart';

/// The shared client for calls against the connected Mutsumi server.
///
/// A single instance keeps one [Dio] — and therefore one connection pool — for
/// the whole app. The access token is read per request instead of being baked
/// into the client, so refreshing it does not force a rebuild.
class AuthenticatedServerClient {
  factory AuthenticatedServerClient({
    SettingsRepository? settingsRepository,
    TokenRefresher? tokenRefresher,
  }) {
    if (settingsRepository == null && tokenRefresher == null) {
      return _shared;
    }
    return AuthenticatedServerClient._(
      settingsRepository ?? SettingsRepository(),
      tokenRefresher ?? TokenRefresher(),
    );
  }

  AuthenticatedServerClient._(this._settings, this._tokenRefresher);

  static final AuthenticatedServerClient _shared = AuthenticatedServerClient._(
    SettingsRepository(),
    TokenRefresher(),
  );

  final SettingsRepository _settings;
  final TokenRefresher _tokenRefresher;

  DioClient? _cachedClient;
  String? _cachedUrl;
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
        _cachedFingerprint != fingerprint) {
      _cachedClient = DioClient(
        url,
        certificateSha256: fingerprint,
        accessTokenProvider: () => _settings.getAccessToken(url),
        refreshAccessToken: () => _tokenRefresher.refresh(url),
      );
      _cachedUrl = url;
      _cachedFingerprint = fingerprint;
    }
    return _cachedClient!.dio;
  }
}
