import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/widgets/app_form_widgets.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/app_glass_background.dart';
import '../../home/presentation/home_page.dart';
import '../data/setup_service.dart';
import '../../auth/presentation/auth_session.dart';

class CreateAdminPage extends StatefulWidget {
  const CreateAdminPage({
    super.key,
    required this.serverUrl,
    this.certificateSha256,
    this.initialServerName = '',
  });

  static const routeName = '/setup/admin';

  final String serverUrl;
  final String? certificateSha256;
  final String initialServerName;

  @override
  State<CreateAdminPage> createState() => _CreateAdminPageState();
}

class _CreateAdminPageState extends State<CreateAdminPage> {
  late final TextEditingController _serverNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  final _initializing = false.obs;

  @override
  void initState() {
    super.initState();
    _serverNameController = TextEditingController(
      text: widget.initialServerName.isEmpty
          ? 'Mutsumi Server'
          : widget.initialServerName,
    );
    _usernameController = TextEditingController(text: 'admin');
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _serverNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  SetupService get _setupService => SetupService(
    widget.serverUrl,
    certificateSha256: widget.certificateSha256,
  );

  Future<void> _initializeServer() async {
    final serverName = _serverNameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (serverName.isEmpty || username.isEmpty || password.isEmpty) {
      await showErrorDialog(title: '无法初始化', message: '请输入服务器名称、管理员账号和密码。');
      return;
    }

    _initializing.value = true;

    try {
      final result = await _setupService.initialize(
        username: username,
        password: password,
        serverName: serverName,
      );
      if (result == null) {
        throw StateError('服务器未返回登录信息');
      }
      await AuthSession.establish(
        serverUrl: widget.serverUrl,
        username: username,
        password: password,
        result: result,
        certificateFingerprint: widget.certificateSha256,
        serverName: serverName,
      );
      if (mounted) {
        Get.offAllNamed(HomePage.routeName);
      }
    } catch (error) {
      await showErrorDialog(title: '初始化失败', message: errorMessageOf(error));
    } finally {
      if (mounted) {
        _initializing.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
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
              AppTextField(controller: _serverNameController, label: '服务器名称'),
              const SizedBox(height: 12),
              AppTextField(controller: _usernameController, label: '管理员账号'),
              const SizedBox(height: 12),
              AppTextField(
                controller: _passwordController,
                obscureText: true,
                label: '管理员密码',
              ),
              const SizedBox(height: 12),
              Obx(
                () => AsyncFilledButton(
                  busy: _initializing.value,
                  onPressed: _initializeServer,
                  icon: Icons.admin_panel_settings,
                  label: '初始化服务器',
                  busyLabel: '正在初始化...',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
