import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/extensions/build_context.dart';
import '../../../core/widgets/app_form_widgets.dart';
import '../../../core/widgets/app_glass_background.dart';
import 'create_admin_controller.dart';

class CreateAdminPage extends GetView<CreateAdminController> {
  const CreateAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      topEdgeFade: true,
      bottomEdgeFade: false,
      enableBackgroundSampling: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        leading: GlassButton(
          width: 40,
          height: 40,
          iconSize: 20,
          icon: const Icon(Icons.arrow_back),
          label: '返回',
          onTap: Get.back,
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: context.pageContentPadding(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '创建管理员账户',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  '服务器未初始化\n请设置服务器名称并创建第一个管理员账户。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                AppTextField(
                  controller: controller.serverNameController,
                  label: '服务器名称',
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: controller.usernameController,
                  label: '管理员账号',
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: controller.passwordController,
                  obscureText: true,
                  label: '管理员密码',
                ),
                const SizedBox(height: 12),
                Obx(
                  () => AsyncFilledButton(
                    busy: controller.initializing.value,
                    onPressed: controller.initializeServer,
                    icon: Icons.admin_panel_settings,
                    label: '初始化服务器',
                    busyLabel: '正在初始化...',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
