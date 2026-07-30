import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/extensions/build_context.dart';
import '../../../core/widgets/app_form_widgets.dart';
import '../../../core/widgets/app_glass_background.dart';
import 'login_controller.dart';

class LoginPage extends GetView<LoginController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      topEdgeFade: true,
      bottomEdgeFade: false,
      extendBody: true,
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
        centerTitle: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: context.pageContentPadding(horizontal: 24),
          child: ConstrainedBox(
            // 表单本身不需要占满宽度；横屏和桌面上限制宽度比拉成一条更好读。
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('登录', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  '服务器已初始化，请使用账号密码登录。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  '服务器：${controller.serverUrl}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                AppTextField(
                  controller: controller.usernameController,
                  label: '账号',
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: controller.passwordController,
                  obscureText: true,
                  label: '密码',
                ),
                const SizedBox(height: 12),
                Obx(
                  () => AsyncFilledButton(
                    busy: controller.loggingIn.value,
                    onPressed: controller.login,
                    icon: Icons.login,
                    label: '登录',
                    busyLabel: '正在登录...',
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
