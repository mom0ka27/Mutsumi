import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';

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

  String? _validateServerInput() {
    if (hostController.text.trim().isEmpty) {
      return '请输入服务器 IP 地址或域名。';
    }

    final port = portController.text.trim();
    if (port.isNotEmpty) {
      final portNumber = int.tryParse(port);
      if (portNumber == null || portNumber < 1 || portNumber > 65535) {
        return '请输入有效端口号。';
      }
    }

    return null;
  }

  Future<void> checkSetupStatus() async {
    final validationMessage = _validateServerInput();
    if (validationMessage != null) {
      await showErrorDialog(title: '无法连接', message: validationMessage);
      return;
    }

    checking.value = true;

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
      await showErrorDialog(
        title: '连接失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      checking.value = false;
    }
  }
}
