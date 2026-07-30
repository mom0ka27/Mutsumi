import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/page_bindings.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/presentation/current_user_controller.dart';
import '../../auth/presentation/login_page.dart';
import '../data/server_info_service.dart';
import '../data/settings_repository.dart';

class SettingsHomeController extends GetxController {
  SettingsHomeController({
    required this.settingsRepository,
    required this.currentUserController,
  });

  final SettingsRepository settingsRepository;
  final CurrentUserController currentUserController;
  final serverVersion = RxnString();
  var _versionServerUrl = '';

  ServerAccount? get currentAccount => settingsRepository.getCurrentAccount();

  bool get isAdmin => currentUserController.isAdmin;

  String serverName(String url) => settingsRepository.getServerName(url);

  void loadServerVersion(ServerAccount? account) {
    if (account == null || _versionServerUrl == account.serverUrl) return;
    _versionServerUrl = account.serverUrl;
    serverVersion.value = null;
    ServerInfoService(
      account.serverUrl,
      certificateSha256: settingsRepository.getCertificateFingerprint(
        account.serverUrl,
      ),
    ).getInfo().then(
      (info) {
        if (_versionServerUrl == account.serverUrl && !isClosed) {
          serverVersion.value = info.version.isEmpty ? '未知' : info.version;
        }
      },
      onError: (_) {
        if (_versionServerUrl == account.serverUrl && !isClosed) {
          serverVersion.value = '获取失败';
        }
      },
    );
  }

  Future<void> addAccount() async {
    final account = currentAccount;
    if (account == null) return;
    final certificateSha256 = settingsRepository.getCertificateFingerprint(
      account.serverUrl,
    );
    final name = serverName(account.serverUrl);
    await Get.to(
      () => const LoginPage(),
      binding: LoginBinding(
        serverUrl: account.serverUrl,
        certificateSha256: certificateSha256,
        serverName: name,
      ),
    );
  }

  Future<void> changePassword() async {
    final account = currentAccount;
    if (account == null) return;
    final currentPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmedPassword = TextEditingController();
    try {
      final confirmed = await showAppDialog<bool>(
        AlertDialog(
          title: const Text('修改密码'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPassword,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '当前密码'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newPassword,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '新密码'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmedPassword,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '确认新密码'),
                ),
              ],
            ),
          ),
          actions: [
            Builder(
              builder: (context) => TextButton(
                onPressed: () => AppDialog.dismiss(context, false),
                child: const Text('取消'),
              ),
            ),
            Builder(
              builder: (context) => FilledButton(
                onPressed: () => AppDialog.dismiss(context, true),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (currentPassword.text.isEmpty || newPassword.text.isEmpty) {
        await showErrorDialog(title: '修改失败', message: '请填写当前密码和新密码');
        return;
      }
      if (newPassword.text != confirmedPassword.text) {
        await showErrorDialog(title: '修改失败', message: '两次输入的新密码不一致');
        return;
      }
      await AuthService(
        account.serverUrl,
        certificateSha256: settingsRepository.getCertificateFingerprint(
          account.serverUrl,
        ),
        accessToken: account.accessToken,
      ).changePassword(
        currentPassword: currentPassword.text,
        newPassword: newPassword.text,
      );
      await settingsRepository.saveLogin(
        serverUrl: account.serverUrl,
        username: account.username,
        password: newPassword.text,
        accessToken: account.accessToken,
        permissionGroup: account.permissionGroup ?? 'User',
      );
      await showInfoDialog(title: '修改成功', message: '密码已更新');
    } catch (error) {
      await showErrorDialog(
        title: '修改失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      currentPassword.dispose();
      newPassword.dispose();
      confirmedPassword.dispose();
    }
  }
}
