import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../app/startup_page.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../setup/presentation/connect_server_page.dart';
import '../data/settings_repository.dart';

class SavedServersPage extends StatefulWidget {
  const SavedServersPage({super.key});

  @override
  State<SavedServersPage> createState() => _SavedServersPageState();
}

class _SavedServersPageState extends State<SavedServersPage> {
  final _repository = SettingsRepository();
  final _revision = 0.obs;

  Future<void> _rename(String url) async {
    var serverName = _repository.getServerName(url);
    final confirmed = await showAppDialog<bool>(
      AlertDialog(
        title: const Text('重命名服务器'),
        content: TextFormField(
          initialValue: serverName,
          autofocus: true,
          decoration: const InputDecoration(labelText: '服务器名称'),
          onChanged: (value) => serverName = value,
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
    if (confirmed == true) {
      try {
        await _repository.renameServer(url, serverName);
        _revision.value++;
        await showInfoDialog(title: '重命名成功', message: '服务器名称已更新');
      } catch (error) {
        await showErrorDialog(
          title: '重命名失败',
          message: errorMessageOf(error),
          error: error,
        );
      }
    }
  }

  Future<void> _removeServer(String url) async {
    final confirmed = await showAppDialog<bool>(
      AlertDialog(
        title: const Text('删除服务器'),
        content: Text('将删除“${_repository.getServerName(url)}”及其所有本地账户信息。'),
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
    if (confirmed == true) {
      try {
        await _repository.removeServer(url);
        if (_repository.getCurrentAccount() == null) {
          Get.offAllNamed(StartupPage.routeName);
        } else {
          _revision.value++;
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
  }

  Future<void> _removeAccount(ServerAccount account) async {
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
    if (confirmed != true) {
      return;
    }
    try {
      await _repository.removeAccount(account.serverUrl, account.username);
      if (_repository.getCurrentAccount() == null) {
        Get.offAllNamed(StartupPage.routeName);
      } else {
        _revision.value++;
        await showInfoDialog(title: '删除成功', message: '账户已删除');
      }
    } catch (error) {
      await showErrorDialog(title: '删除失败', message: errorMessageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('已保存服务器', style: Theme.of(context).textTheme.titleLarge),
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
        actions: [
          GlassButton(
            width: 40,
            height: 40,
            iconSize: 20,
            icon: const Icon(Icons.add_link_rounded),
            label: '添加新服务器',
            onTap: () => Get.to(
              () => const ConnectServerPage(
                prefillLastServer: false,
                showBackButton: true,
              ),
            ),
          ),
        ],
        centerTitle: false,
      ),
      body: Obx(() {
        _revision.value;
        final servers = _repository.getServerUrls();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, Constants.topPadding, 16, 16),
          itemCount: servers.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final url = servers[index];
            final accounts = _repository.getAccounts(url);
            return GlassCard(
              useOwnLayer: true,
              padding: const EdgeInsets.all(16),
              shape: LiquidRoundedSuperellipse(
                borderRadius: Constants.radius.x,
              ),
              settings: AppGlassSettings.standard(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(child: const Icon(Icons.dns_rounded)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _repository.getServerName(url),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              url,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _rename(url),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        onPressed: () => _removeServer(url),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  const Divider(),
                  ...accounts.map(
                    (account) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(account.username),
                      trailing: IconButton(
                        onPressed: () => _removeAccount(account),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      onTap: () async {
                        try {
                          await _repository.setCurrentAccount(
                            account.serverUrl,
                            account.username,
                          );
                          Get.offAllNamed(StartupPage.routeName);
                        } catch (error) {
                          await showErrorDialog(
                            title: '切换账户失败',
                            message: errorMessageOf(error),
                            error: error,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}
