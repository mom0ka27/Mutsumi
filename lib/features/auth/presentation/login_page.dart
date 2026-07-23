import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_form_widgets.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../home/presentation/home_page.dart';
import '../data/auth_service.dart';
import 'auth_session.dart';

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
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  final _loggingIn = false.obs;

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
      await showErrorDialog(title: '无法登录', message: '请输入账号和密码。');
      return;
    }

    _loggingIn.value = true;

    try {
      final result = await _authService.login(
        username: username,
        password: password,
      );
      if (result == null) {
        throw StateError('服务器未返回登录信息');
      }
      await AuthSession.establish(
        serverUrl: widget.serverUrl,
        username: username,
        password: password,
        result: result,
        certificateFingerprint: widget.certificateSha256,
        serverName: widget.serverName,
      );
      if (mounted) {
        Get.offAllNamed(HomePage.routeName);
      }
    } catch (error) {
      await showErrorDialog(
        title: '登录失败',
        message: errorMessageOf(error),
        error: error,
      );
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
            mainAxisSize: MainAxisSize.min,
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
              AppTextField(controller: _usernameController, label: '账号'),
              const SizedBox(height: 12),
              AppTextField(
                controller: _passwordController,
                obscureText: true,
                label: '密码',
              ),
              const SizedBox(height: 12),
              Obx(
                () => AsyncFilledButton(
                  busy: _loggingIn.value,
                  onPressed: _login,
                  icon: Icons.login,
                  label: '登录',
                  busyLabel: '正在登录...',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
