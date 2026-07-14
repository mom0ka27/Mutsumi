import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../features/auth/data/auth_service.dart';
import '../features/auth/presentation/auth_session.dart';
import '../features/home/presentation/home_page.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/setup/presentation/connect_server_page.dart';
import '../core/widgets/app_glass_background.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  static const routeName = '/';

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  final _settingsRepository = SettingsRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
    });
  }

  Future<void> _autoConnect() async {
    final serverUrl = _settingsRepository.getCurrentServerUrl();
    if (serverUrl == null || serverUrl.isEmpty) {
      _goToConnectServer();
      return;
    }

    final credential = await _settingsRepository.getServerCredential(serverUrl);
    if (credential == null) {
      _goToConnectServer();
      return;
    }

    try {
      final result = await AuthService(
        serverUrl,
        certificateSha256: _settingsRepository.getCertificateFingerprint(
          serverUrl,
        ),
      ).login(username: credential.username, password: credential.password);

      if (result == null) {
        throw StateError('服务器未返回登录信息');
      }
      await AuthSession.establish(
        serverUrl: serverUrl,
        username: credential.username,
        password: credential.password,
        result: result,
        certificateFingerprint: _settingsRepository.getCertificateFingerprint(
          serverUrl,
        ),
        serverName: _settingsRepository.getServerName(serverUrl),
      );
      if (mounted) {
        Get.offAllNamed(HomePage.routeName);
      }
    } catch (_) {
      _goToConnectServer();
    }
  }

  void _goToConnectServer() {
    if (!mounted) {
      return;
    }

    Get.offAllNamed(ConnectServerPage.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GlassScaffold(
      enableBackgroundSampling: true,
      background: const AppGlassBackground(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_sync_rounded,
              size: 56,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('正在连接服务器', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
