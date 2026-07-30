import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../app/page_bindings.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../../core/extensions/build_context.dart';
import '../../users/presentation/users_management_page.dart';
import 'qbittorrent_settings_view.dart';
import 'storage_status_page.dart';
import 'appearance_settings_page.dart';
import 'player_settings_page.dart';
import 'saved_servers_page.dart';
import 'saved_servers_binding.dart';
import 'server_update_page.dart';
import 'settings_home_controller.dart';

class SettingsHomeView extends GetView<SettingsHomeController> {
  const SettingsHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final account = controller.currentAccount;
      controller.loadServerVersion(account);
      final colors = Theme.of(context).colorScheme;
      final glassSettings = AppGlassSettings.standard(context);
      return ListView(
        padding: context.homeContentPadding(),
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        account == null
                            ? '未连接服务器'
                            : controller.serverName(account.serverUrl),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (account != null)
                        Text(
                          account.serverUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      if (account != null)
                        Obx(
                          () => Text(
                            '服务端版本：${controller.serverVersion.value ?? '获取中...'}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
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
                  onTap: () => Get.to(
                    () => const SavedServersPage(),
                    binding: SavedServersBinding(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: const Text('添加账户'),
                  subtitle: const Text('登录当前服务器的其他账户'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: account == null ? null : controller.addAccount,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('修改密码'),
                  subtitle: const Text('更新当前账户的登录密码'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: account == null ? null : controller.changePassword,
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
          const SizedBox(height: 20),
          GlassCard(
            useOwnLayer: true,
            padding: EdgeInsets.zero,
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            settings: glassSettings,
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('播放器'),
              subtitle: const Text('后台播放、倍速与长按倍速'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Get.to(() => const PlayerSettingsPage()),
            ),
          ),
          if (controller.isAdmin) ...[
            const SizedBox(height: 20),
            GlassCard(
              useOwnLayer: true,
              padding: EdgeInsets.zero,
              shape: LiquidRoundedSuperellipse(
                borderRadius: Constants.radius.x,
              ),
              settings: glassSettings,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.download_rounded),
                    title: const Text('qBittorrent'),
                    subtitle: const Text('下载与分享率设置'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Get.to(
                      () => const QBittorrentSettingsPage(),
                      binding: QBittorrentSettingsBinding(),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_rounded),
                    title: const Text('用户管理'),
                    subtitle: const Text('新增、编辑和删除用户'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Get.to(
                      () => const UsersManagementPage(),
                      binding: UsersManagementBinding(),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.storage_rounded),
                    title: const Text('存储空间'),
                    subtitle: const Text('查看 data 文件夹和服务器磁盘容量'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Get.to(
                      () => const StorageStatusPage(),
                      binding: StorageStatusBinding(),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.system_update_rounded),
                    title: const Text('服务端更新'),
                    subtitle: const Text('检查并安装 GitHub 发布版本或分支更新'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Get.to(
                      () => const ServerUpdatePage(),
                      binding: ServerUpdateBinding(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}
