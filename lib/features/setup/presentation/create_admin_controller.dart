import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../app/app_routes.dart';
import '../../auth/presentation/auth_session.dart';
import '../data/setup_service.dart';

class CreateAdminController extends GetxController {
  CreateAdminController({
    required this.serverUrl,
    this.certificateSha256,
    this.initialServerName = '',
    SetupService? setupService,
    AuthSession? authSession,
  }) : _setupService =
           setupService ??
           SetupService(serverUrl, certificateSha256: certificateSha256),
       _authSession = authSession ?? AuthSession();

  final String serverUrl;
  final String? certificateSha256;
  final String initialServerName;
  final SetupService _setupService;
  final AuthSession _authSession;
  final initializing = false.obs;
  late final TextEditingController serverNameController;
  final usernameController = TextEditingController(text: 'admin');
  final passwordController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    serverNameController = TextEditingController(
      text: initialServerName.isEmpty ? 'Mutsumi Server' : initialServerName,
    );
  }

  String? validateInput() {
    if (serverNameController.text.trim().isEmpty ||
        usernameController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      return '请输入服务器名称、管理员账号和密码。';
    }
    return null;
  }

  Future<void> initializeServer() async {
    final validationMessage = validateInput();
    if (validationMessage != null) {
      await showErrorDialog(title: '无法初始化', message: validationMessage);
      return;
    }

    final normalizedServerName = serverNameController.text.trim();
    final normalizedUsername = usernameController.text.trim();
    final password = passwordController.text;

    initializing.value = true;
    try {
      final result = await _setupService.initialize(
        username: normalizedUsername,
        password: password,
        serverName: normalizedServerName,
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
        serverName: normalizedServerName,
      );
      if (!isClosed) {
        unawaited(Get.offAllNamed(AppRoutes.home));
      }
    } catch (error) {
      await showErrorDialog(
        title: '初始化失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (!isClosed) {
        initializing.value = false;
      }
    }
  }

  @override
  void onClose() {
    serverNameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
