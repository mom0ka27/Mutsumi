import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../home/presentation/home_page.dart';
import '../../settings/data/settings_repository.dart';
import '../data/auth_service.dart';

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

  bool _loggingIn = false;
  String? _message;

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
      setState(() {
        _message = '请输入账号和密码。';
      });
      return;
    }

    setState(() {
      _loggingIn = true;
      _message = null;
    });

    try {
      final token = await _authService.login(
        username: username,
        password: password,
      );
      if (token != null) {
        await _settingsRepository.addServerUrl(
          widget.serverUrl,
          certificateFingerprint: widget.certificateSha256,
          serverName: widget.serverName,
        );
        await _settingsRepository.setServerCredential(
          widget.serverUrl,
          username: username,
          password: password,
        );
        await _settingsRepository.setAccessToken(widget.serverUrl, token);
      }
      if (mounted) {
        Get.offAllNamed(HomePage.routeName);
      }
    } on DioException catch (error) {
      final detail = error.response?.data is Map<String, dynamic>
          ? error.response?.data['detail']
          : null;
      setState(() {
        _message = '登录失败：${detail ?? error.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loggingIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录 Mutsumi')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
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
              FilledButton.icon(
                onPressed: _loggingIn ? null : _login,
                icon: _loggingIn
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(_loggingIn ? '正在登录...' : '登录'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_message!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
