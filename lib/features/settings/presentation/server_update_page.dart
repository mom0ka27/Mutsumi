import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../../core/extensions/build_context.dart';

import '../../../core/widgets/app_glass_background.dart';
import 'server_update_controller.dart';
import 'server_update_widgets.dart';

class ServerUpdatePage extends GetView<ServerUpdateController> {
  const ServerUpdatePage({super.key});

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
        title: Text('服务端更新', style: Theme.of(context).textTheme.titleLarge),
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
            icon: const Icon(Icons.refresh_rounded),
            label: '刷新',
            onTap: () {
              if (!controller.loading.value && !controller.applying.value) {
                controller.load();
              }
            },
          ),
        ],
        centerTitle: false,
      ),
      body: Obx(() => _buildBody(context, controller)),
    );
  }

  Widget _buildBody(BuildContext context, ServerUpdateController controller) {
    return Center(
      child: SingleChildScrollView(
        padding: context.pageContentPadding(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: UpdateInfoCard(
            channel: controller.channel.value,
            info: controller.info.value,
            errorMessage: controller.errorMessage.value,
            loading: controller.loading.value,
            applying: controller.applying.value,
            updateStatus: controller.updateStatus.value,
            onChannelChanged: controller.changeChannel,
            onApply: controller.apply,
          ),
        ),
      ),
    );
  }
}
