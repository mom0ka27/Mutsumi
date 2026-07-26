import 'package:get/get.dart';

import '../../../core/logging/app_logger.dart';
import '../../settings/data/settings_repository.dart';
import '../presentation/current_user_controller.dart';
import 'auth_service.dart';

/// Performs the login round-trip. Injectable so tests can drive the refresh
/// logic without a server.
typedef LoginCallback =
    Future<LoginResult?> Function(
      String serverUrl,
      String? certificateSha256,
      ServerCredential credential,
    );

/// Re-logs in with the stored credentials when the access token expires.
///
/// Tokens are valid for a day, so without this every request after expiry fails
/// until the app is restarted. Concurrent refreshes for the same server share a
/// single login round-trip.
class TokenRefresher {
  TokenRefresher({SettingsRepository? settingsRepository, LoginCallback? login})
    : _settings = settingsRepository ?? SettingsRepository(),
      _login = login ?? _defaultLogin;

  final SettingsRepository _settings;
  final LoginCallback _login;

  static Future<LoginResult?> _defaultLogin(
    String serverUrl,
    String? certificateSha256,
    ServerCredential credential,
  ) {
    return AuthService(
      serverUrl,
      certificateSha256: certificateSha256,
    ).login(username: credential.username, password: credential.password);
  }

  String? _pendingServerUrl;
  Future<String?>? _pending;

  Future<String?> refresh(String serverUrl) {
    final pending = _pending;
    if (pending != null && _pendingServerUrl == serverUrl) {
      return pending;
    }
    final future = _refresh(serverUrl);
    _pendingServerUrl = serverUrl;
    _pending = future;
    return future.whenComplete(() {
      if (identical(_pending, future)) {
        _pending = null;
        _pendingServerUrl = null;
      }
    });
  }

  Future<String?> _refresh(String serverUrl) async {
    final credential = await _settings.getServerCredential(serverUrl);
    if (credential == null) {
      AppLogger.info('登录状态已过期，但没有可用于重新登录的凭据', tag: 'Auth');
      return null;
    }

    AppLogger.info('登录状态已过期，正在重新登录', tag: 'Auth');
    final result = await _login(
      serverUrl,
      _settings.getCertificateFingerprint(serverUrl),
      credential,
    );
    if (result == null) {
      return null;
    }

    await _settings.setAccessToken(serverUrl, result.accessToken);
    if (Get.isRegistered<CurrentUserController>()) {
      Get.find<CurrentUserController>().setPermissionGroup(
        result.permissionGroup,
      );
    }
    AppLogger.info('重新登录成功', tag: 'Auth');
    return result.accessToken;
  }
}
