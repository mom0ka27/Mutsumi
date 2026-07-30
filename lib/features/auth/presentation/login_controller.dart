import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../app/app_routes.dart';
import '../data/auth_service.dart';
import 'auth_session.dart';

class LoginController extends GetxController {
  LoginController({
    required this.serverUrl,
    this.certificateSha256,
    this.serverName,
    AuthService? authService,
    AuthSession? authSession,
  }) : _authService =
           authService ??
           AuthService(serverUrl, certificateSha256: certificateSha256),
       _authSession = authSession ?? AuthSession();

  final String serverUrl;
  final String? certificateSha256;
  final String? serverName;
  final AuthService _authService;
  final AuthSession _authSession;
  final loggingIn = false.obs;
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  String? validateInput() {
    if (usernameController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      return '请输入账号和密码。';
    }
    return null;
  }

  Future<void> login() async {
    final validationMessage = validateInput();
    if (validationMessage != null) {
      await showErrorDialog(title: '无法登录', message: validationMessage);
      return;
    }

    final normalizedUsername = usernameController.text.trim();
    final password = passwordController.text;

    loggingIn.value = true;
    try {
      final result = await _authService.login(
        username: normalizedUsername,
        password: password,
      );
      if (result == null) {
        throw StateError('服务器未返回登录信息');
      }
      await _authSession.establish(
        serverUrl: serverUrl,
        username: normalizedUsername,
        password: password,
        result: result,
        certificateFingerprint: certificateSha256,
        serverName: serverName,
      );
      if (!isClosed) {
        unawaited(Get.offAllNamed(AppRoutes.home));
      }
    } catch (error) {
      await showErrorDialog(
        title: '登录失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (!isClosed) {
        loggingIn.value = false;
      }
    }
  }

  @override
  void onClose() {
    usernameController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
