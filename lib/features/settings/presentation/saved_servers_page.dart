import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';
import '../../../core/extensions/build_context.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../setup/presentation/connect_server_page.dart';
import '../../setup/presentation/connect_server_binding.dart';
import 'saved_servers_controller.dart';

class SavedServersPage extends GetView<SavedServersController> {
  const SavedServersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      topEdgeFade: true,
      bottomEdgeFade: false,
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
              binding: ConnectServerBinding(prefillLastServer: false),
            ),
          ),
        ],
        centerTitle: false,
      ),
      body: Obx(() {
        controller.revision.value;
        final servers = controller.serverUrls;
        return ListView.separated(
          padding: context.pageContentPadding(horizontal: 16, bottom: 16),
          itemCount: servers.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final url = servers[index];
            final accounts = controller.accounts(url);
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
                              controller.serverName(url),
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
                        onPressed: () => controller.rename(url),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        onPressed: () => controller.removeServer(url),
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
                        onPressed: () => controller.removeAccount(account),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      onTap: () => controller.selectAccount(account),
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
