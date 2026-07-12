import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../home/presentation/home_page.dart';
import '../../settings/data/settings_repository.dart';
import '../data/auth_service.dart';
import 'current_user_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.serverUrl,
    this.certificateSha256,
    this.serverName,
  });

  final String serverUrl;
  final String? certificateSha256;
  final String? serverName;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _settingsRepository = SettingsRepository();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  final _loggingIn = false.obs;
  final _message = RxnString();

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  AuthService get _authService => AuthService(
    widget.serverUrl,
    certificateSha256: widget.certificateSha256,
  );

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _message.value = '请输入账号和密码。';
      return;
    }

    _loggingIn.value = true;
    _message.value = null;

    try {
      final result = await _authService.login(
        username: username,
        password: password,
      );
      if (result == null) {
        throw StateError('服务器未返回登录信息');
      }
      await _settingsRepository.saveLogin(
        serverUrl: widget.serverUrl,
        username: username,
        password: password,
        accessToken: result.accessToken,
        permissionGroup: result.permissionGroup,
        certificateFingerprint: widget.certificateSha256,
        serverName: widget.serverName,
      );
      CurrentUserController.instance.setPermissionGroup(result.permissionGroup);
      if (mounted) {
        Get.offAllNamed(HomePage.routeName);
      }
    } on DioException catch (error) {
      final detail = error.response?.data is Map<String, dynamic>
          ? error.response?.data['detail']
          : null;
      _message.value = '登录失败：${detail ?? error.message}';
    } finally {
      if (mounted) {
        _loggingIn.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      extendBody: true,
      enableBackgroundSampling: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          '登录 Mutsumi',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
        centerTitle: false,
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(24, Constants.topPadding, 24, 24),
        child: Center(
          child: Column(
            children: [
              Text('登录', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                '服务器已初始化，请使用账号密码登录。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '服务器：${widget.serverUrl}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '账号',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => FilledButton.icon(
                  onPressed: _loggingIn.value ? null : _login,
                  icon: _loggingIn.value
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(_loggingIn.value ? '正在登录...' : '登录'),
                ),
              ),
              Obx(() {
                final message = _message.value;
                if (message == null) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(message),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
