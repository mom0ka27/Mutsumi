import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/dio_client.dart';
import '../../users/presentation/users_management_page.dart';
import '../data/settings_repository.dart';
import 'qbittorrent_settings_view.dart';
import 'saved_servers_page.dart';

class SettingsHomeView extends StatefulWidget {
  const SettingsHomeView({super.key, this.bottomPadding = 120});

  final double bottomPadding;

  @override
  State<SettingsHomeView> createState() => _SettingsHomeViewState();
}

class _SettingsHomeViewState extends State<SettingsHomeView> {
  final _settings = SettingsRepository();
  final _loading = true.obs;
  final _isAdmin = false.obs;

  @override
  void initState() {
    super.initState();
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    final url = _settings.getServerUrl();
    try {
      final response = await DioClient(
        url,
        certificateSha256: _settings.getCertificateFingerprint(url),
        accessToken: _settings.getAccessToken(url),
      ).dio.get<Map<String, dynamic>>(currentUserApiPath);
      _isAdmin.value = response.data?['permission_group'] == 'Admin';
    } catch (_) {
      _isAdmin.value = false;
    } finally {
      _loading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) => Obx(
    () => ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, widget.bottomPadding),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        GlassCard(
          useOwnLayer: true,
          padding: EdgeInsets.zero,
          shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
          settings: LiquidGlassSettings.figma(
            refraction: 36,
            depth: 22,
            dispersion: 6,
            frost: 5,
            glassColor: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.3),
          ),
          child: ListTile(
            leading: const Icon(Icons.dns_rounded),
            title: const Text('已保存服务器'),
            subtitle: const Text('切换、重命名或删除服务器与账户'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Get.to(() => const SavedServersPage()),
          ),
        ),
        if (_loading.value) ...[
          const SizedBox(height: 32),
          const Center(child: CircularProgressIndicator()),
        ] else if (_isAdmin.value) ...[
          const SizedBox(height: 20),
          GlassCard(
            useOwnLayer: true,
            padding: EdgeInsets.zero,
            shape: LiquidRoundedSuperellipse(borderRadius: Constants.radius.x),
            settings: LiquidGlassSettings.figma(
              refraction: 36,
              depth: 22,
              dispersion: 6,
              frost: 5,
              glassColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.3),
            ),
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
    ),
  );
}
