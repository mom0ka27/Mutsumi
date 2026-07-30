import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/app_routes.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/settings_repository.dart';

class SavedServersController extends GetxController {
  SavedServersController({required this.settingsRepository});

  final SettingsRepository settingsRepository;
  final revision = 0.obs;

  List<String> get serverUrls => settingsRepository.getServerUrls();

  String serverName(String url) => settingsRepository.getServerName(url);

  List<ServerAccount> accounts(String url) =>
      settingsRepository.getAccounts(url);

  Future<void> rename(String url) async {
    var name = serverName(url);
    final confirmed = await showAppDialog<bool>(
      AlertDialog(
        title: const Text('重命名服务器'),
        content: TextFormField(
          initialValue: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '服务器名称'),
          onChanged: (value) => name = value,
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
    try {
      await settingsRepository.renameServer(url, name);
      revision.value++;
      await showInfoDialog(title: '重命名成功', message: '服务器名称已更新');
    } catch (error) {
      await showErrorDialog(
        title: '重命名失败',
        message: errorMessageOf(error),
        error: error,
      );
    }
  }

  Future<void> removeServer(String url) async {
    final confirmed = await showAppDialog<bool>(
      AlertDialog(
        title: const Text('删除服务器'),
        content: Text('将删除“${serverName(url)}”及其所有本地账户信息。'),
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
              child: const Text('删除'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await settingsRepository.removeServer(url);
      if (settingsRepository.getCurrentAccount() == null) {
        unawaited(Get.offAllNamed(AppRoutes.startup));
      } else {
        revision.value++;
        await showInfoDialog(title: '删除成功', message: '服务器已删除');
      }
    } catch (error) {
      await showErrorDialog(
        title: '删除失败',
        message: errorMessageOf(error),
        error: error,
      );
    }
  }

  Future<void> removeAccount(ServerAccount account) async {
    final confirmed = await showAppDialog<bool>(
      AlertDialog(
        title: const Text('删除账户'),
        content: Text(
          '确定删除“${account.username}”吗？\n\n只会删除此设备保存的登录信息，不会删除服务器上的用户。',
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
              child: const Text('删除'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await settingsRepository.removeAccount(
        account.serverUrl,
        account.username,
      );
      if (settingsRepository.getCurrentAccount() == null) {
        unawaited(Get.offAllNamed(AppRoutes.startup));
      } else {
        revision.value++;
        await showInfoDialog(title: '删除成功', message: '账户已删除');
      }
    } catch (error) {
      await showErrorDialog(
        title: '删除失败',
        message: errorMessageOf(error),
        error: error,
      );
    }
  }

  Future<void> selectAccount(ServerAccount account) async {
    try {
      await settingsRepository.setCurrentAccount(
        account.serverUrl,
        account.username,
      );
      unawaited(Get.offAllNamed(AppRoutes.startup));
    } catch (error) {
      await showErrorDialog(
        title: '切换账户失败',
        message: errorMessageOf(error),
        error: error,
      );
    }
  }
}
