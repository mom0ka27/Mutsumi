import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/presentation/login_page.dart';
import '../../settings/data/settings_repository.dart';
import '../data/setup_service.dart';
import 'create_admin_page.dart';

class ConnectServerController extends GetxController {
  ConnectServerController({this.prefillLastServer = true});

  final bool prefillLastServer;
  final settingsRepository = SettingsRepository();
  final scheme = 'http'.obs;
  final checking = false.obs;
  final message = RxnString();

  late final TextEditingController hostController;
  late final TextEditingController portController;
  late final TextEditingController certificateFingerprintController;
  late final String initialServerUrl;

  String get serverUrl {
    final host = hostController.text.trim();
    final port = portController.text.trim();
    if (port.isEmpty) {
      return '${scheme.value}://$host';
    }
    return '${scheme.value}://$host:$port';
  }

  String? get certificateSha256 {
    final value = certificateFingerprintController.text.trim();
    return value.isEmpty ? null : value;
  }

  SetupService get setupService =>
      SetupService(serverUrl, certificateSha256: certificateSha256);

  @override
  void onInit() {
    super.onInit();
    final savedServerUrl = prefillLastServer
        ? settingsRepository.getServerUrl()
        : '';
    initialServerUrl = savedServerUrl;
    final serverUri = Uri.tryParse(savedServerUrl);
    scheme.value = serverUri?.scheme == 'https' ? 'https' : 'http';
    hostController = TextEditingController(text: serverUri?.host ?? '');
    portController = TextEditingController(
      text: serverUri?.hasPort == true ? serverUri!.port.toString() : '12091',
    );
    certificateFingerprintController = TextEditingController(
      text: settingsRepository.getCertificateFingerprint(savedServerUrl) ?? '',
    );
  }

  @override
  void onClose() {
    hostController.dispose();
    portController.dispose();
    certificateFingerprintController.dispose();
    super.onClose();
  }

  void setScheme(String value) {
    scheme.value = value;
  }

  bool validateServerInput() {
    if (hostController.text.trim().isEmpty) {
      message.value = '请输入服务器 IP 地址或域名。';
      return false;
    }

    final port = portController.text.trim();
    if (port.isNotEmpty) {
      final portNumber = int.tryParse(port);
      if (portNumber == null || portNumber < 1 || portNumber > 65535) {
        message.value = '请输入有效端口号。';
        return false;
      }
    }

    return true;
  }

  Future<void> checkSetupStatus() async {
    if (!validateServerInput()) {
      return;
    }

    if (settingsRepository.hasServerUrl(serverUrl) &&
        serverUrl != initialServerUrl) {
      message.value = '该服务器已添加，请在主页左上角服务器列表中选择。';
      return;
    }

    checking.value = true;
    message.value = null;

    try {
      final status = await setupService.getStatus();
      if (status.initialized) {
        await Get.to(
          () => LoginPage(
            serverUrl: serverUrl,
            certificateSha256: certificateSha256,
            serverName: status.serverName,
          ),
        );
      } else {
        await Get.to(
          () => CreateAdminPage(
            serverUrl: serverUrl,
            certificateSha256: certificateSha256,
            initialServerName: status.serverName,
          ),
        );
      }
    } on DioException catch (error) {
      message.value = '连接失败\n${error.toString()}';
    } finally {
      checking.value = false;
    }
  }
}
