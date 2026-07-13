import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_form_widgets.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_glass_settings.dart';
import 'connect_server_controller.dart';

class ConnectServerPage extends StatelessWidget {
  const ConnectServerPage({
    super.key,
    this.prefillLastServer = true,
    this.showBackButton = false,
  });

  final bool prefillLastServer;
  final bool showBackButton;

  static const routeName = '/setup';

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(
      ConnectServerController(prefillLastServer: prefillLastServer),
    );
    final colorScheme = Theme.of(context).colorScheme;

    return GlassScaffold(
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('连接服务器', style: Theme.of(context).textTheme.titleLarge),
        leading: showBackButton
            ? GlassButton(
                width: 40,
                height: 40,
                iconSize: 20,
                icon: const Icon(Icons.arrow_back),
                label: '返回',
                onTap: Get.back,
              )
            : null,
        centerTitle: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, Constants.topPadding, 24, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassCard(
              useOwnLayer: true,
              padding: const EdgeInsets.all(28),
              shape: LiquidRoundedSuperellipse(
                borderRadius: Constants.radius.x,
              ),
              settings: AppGlassSettings.standard(context),
              child: Obx(
                () => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.cloud_sync_rounded,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '连接 Mutsumi Server',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '输入服务器地址，客户端会自动检查是否需要初始化。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'http',
                          icon: Icon(Icons.public),
                          label: Text('HTTP'),
                        ),
                        ButtonSegment(
                          value: 'https',
                          icon: Icon(Icons.lock_outline),
                          label: Text('HTTPS'),
                        ),
                      ],
                      selected: {controller.scheme.value},
                      onSelectionChanged: (values) {
                        controller.setScheme(values.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: controller.hostController,
                      label: 'IP 地址或域名',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: controller.portController,
                      label: '端口',
                      hintText: '例如：12091',
                      prefixIcon: const Icon(Icons.tag),
                      keyboardType: TextInputType.number,
                    ),
                    if (controller.scheme.value == 'https') ...[
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: controller.certificateFingerprintController,
                        label: '证书 SHA-256 指纹（可选）',
                        prefixIcon: const Icon(Icons.fingerprint),
                        keyboardType: TextInputType.text,
                      ),
                    ],
                    const SizedBox(height: 20),
                    AsyncFilledButton(
                      busy: controller.checking.value,
                      onPressed: controller.checkSetupStatus,
                      icon: Icons.arrow_forward_rounded,
                      label: '连接并检查',
                      busyLabel: '正在连接...',
                    ),
                    FormStatusMessage(
                      message: controller.message.value,
                      isError: true,
                      topSpacing: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
