import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../auth/presentation/login_page.dart';
import '../../auth/presentation/current_user_controller.dart';
import '../../setup/presentation/connect_server_page.dart';
import '../../users/presentation/users_management_page.dart';
import '../data/settings_repository.dart';
import 'qbittorrent_settings_view.dart';
import 'appearance_settings_page.dart';
import 'saved_servers_page.dart';

class SettingsHomeView extends StatefulWidget {
  const SettingsHomeView({super.key, this.bottomPadding = 120});

  final double bottomPadding;

  @override
  State<SettingsHomeView> createState() => _SettingsHomeViewState();
}

class _SettingsHomeViewState extends State<SettingsHomeView> {
  final _settings = SettingsRepository();
  final _currentUser = CurrentUserController.instance;

  Future<void> _addAccount() async {
    final account = _settings.getCurrentAccount();
    if (account == null) return;
    await Get.to(
      () => LoginPage(
        serverUrl: account.serverUrl,
        certificateSha256: _settings.getCertificateFingerprint(
          account.serverUrl,
        ),
        serverName: _settings.getServerName(account.serverUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final account = _settings.getCurrentAccount();
    final colors = Theme.of(context).colorScheme;
    final glassSettings = LiquidGlassSettings.figma(
      refraction: 36,
      depth: 22,
      dispersion: 6,
      frost: 5,
      glassColor: colors.surface.withValues(alpha: 0.3),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, widget.bottomPadding),
      children: [
        GlassCard(
          useOwnLayer: true,
          padding: const EdgeInsets.all(20),
          shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
          settings: glassSettings,
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.person_rounded),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account?.username ?? '未登录',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account == null
                          ? '未连接服务器'
                          : _settings.getServerName(account.serverUrl),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (account != null)
                      Text(
                        account.serverUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          useOwnLayer: true,
          padding: EdgeInsets.zero,
          shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
          settings: glassSettings,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.switch_account_rounded),
                title: const Text('切换账户'),
                subtitle: const Text('管理已保存的服务器与账户'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Get.to(() => const SavedServersPage()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_rounded),
                title: const Text('添加账户'),
                subtitle: const Text('登录当前服务器的其他账户'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: account == null ? null : _addAccount,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_link_rounded),
                title: const Text('连接新服务器'),
                subtitle: const Text('添加并登录另一台服务器'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Get.to(
                  () => const ConnectServerPage(
                    prefillLastServer: false,
                    showBackButton: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          useOwnLayer: true,
          padding: EdgeInsets.zero,
          shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
          settings: glassSettings,
          child: ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('外观'),
            subtitle: const Text('调整主题模式'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Get.to(() => const AppearanceSettingsPage()),
          ),
        ),
        if (_currentUser.isAdmin) ...[
          const SizedBox(height: 20),
          GlassCard(
            useOwnLayer: true,
            padding: EdgeInsets.zero,
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            settings: glassSettings,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('qBittorrent'),
                  subtitle: const Text('下载与分享率设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Get.to(() => const QBittorrentSettingsPage()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_rounded),
                  title: const Text('用户管理'),
                  subtitle: const Text('新增、编辑和删除用户'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Get.to(() => const UsersManagementPage()),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  });
}
