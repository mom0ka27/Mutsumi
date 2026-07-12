import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_glass_background.dart';
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
              settings: LiquidGlassSettings.figma(
                refraction: 42,
                depth: 26,
                dispersion: 8,
                frost: 5,
                glassColor: colorScheme.surface.withValues(alpha: 0.32),
              ),
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
                    TextField(
                      controller: controller.hostController,
                      decoration: const InputDecoration(
                        labelText: 'IP 地址或域名',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller.portController,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        hintText: '例如：12091',
                        prefixIcon: Icon(Icons.tag),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    if (controller.scheme.value == 'https') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller.certificateFingerprintController,
                        decoration: const InputDecoration(
                          labelText: '证书 SHA-256 指纹（可选）',
                          prefixIcon: Icon(Icons.fingerprint),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.text,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: controller.checking.value
                          ? null
                          : controller.checkSetupStatus,
                      icon: controller.checking.value
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded),
                      label: Text(
                        controller.checking.value ? '正在连接...' : '连接并检查',
                      ),
                    ),
                    if (controller.message.value != null) ...[
                      const SizedBox(height: 16),
                      Card.filled(
                        color: colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            controller.message.value!,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
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
