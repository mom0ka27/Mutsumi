import 'dart:async';

import 'package:get/get.dart';

import '../core/logging/app_logger.dart';
import 'app_routes.dart';
import '../features/auth/data/auth_service.dart';
import '../features/auth/presentation/auth_session.dart';
import '../features/settings/data/settings_repository.dart';

class StartupController extends GetxController {
  StartupController({
    SettingsRepository? settingsRepository,
    AuthSession? authSession,
  }) : _settingsRepository = settingsRepository ?? SettingsRepository(),
       _authSession = authSession ?? AuthSession();

  final SettingsRepository _settingsRepository;
  final AuthSession _authSession;

  @override
  void onReady() {
    super.onReady();
    autoConnect();
  }

  Future<void> autoConnect() async {
    final serverUrl = _settingsRepository.getCurrentServerUrl();
    if (serverUrl == null || serverUrl.isEmpty) {
      _goToSavedServers();
      return;
    }

    final credential = await _settingsRepository.getServerCredential(serverUrl);
    if (credential == null) {
      _goToSavedServers();
      return;
    }

    try {
      final certificateFingerprint = _settingsRepository
          .getCertificateFingerprint(serverUrl);
      final result = await AuthService(
        serverUrl,
        certificateSha256: certificateFingerprint,
      ).login(username: credential.username, password: credential.password);
      if (result == null) {
        throw StateError('服务器未返回登录信息');
      }
      await _authSession.establish(
        serverUrl: serverUrl,
        username: credential.username,
        password: credential.password,
        result: result,
        certificateFingerprint: certificateFingerprint,
        serverName: _settingsRepository.getServerName(serverUrl),
      );
      if (!isClosed) {
        unawaited(Get.offAllNamed(AppRoutes.home));
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        '自动连接服务器失败',
        tag: 'Startup',
        error: error,
        stackTrace: stackTrace,
      );
      _goToSavedServers();
    }
  }

  void _goToSavedServers() {
    if (!isClosed) {
      Get.offAllNamed(AppRoutes.savedServers);
    }
  }
}
