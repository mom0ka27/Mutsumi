import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../home/presentation/home_page.dart';
import '../../settings/data/settings_repository.dart';
import '../data/setup_service.dart';
import '../../auth/presentation/current_user_controller.dart';

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
  final _settingsRepository = SettingsRepository();
  late final TextEditingController _serverNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  final _initializing = false.obs;
  final _message = RxnString();

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
      _message.value = '请输入服务器名称、管理员账号和密码。';
      return;
    }

    _initializing.value = true;
    _message.value = null;

    try {
      final result = await _setupService.initialize(
        username: username,
        password: password,
        serverName: serverName,
      );
      if (result == null) {
        throw StateError('服务器未返回登录信息');
      }
      await _settingsRepository.saveLogin(
        serverUrl: widget.serverUrl,
        username: username,
        password: password,
        accessToken: result.accessToken,
        permissionGroup: result.permissionGroup,
        certificateFingerprint: widget.certificateSha256,
        serverName: serverName,
      );
      CurrentUserController.instance.setPermissionGroup(result.permissionGroup);
      if (mounted) {
        Get.offAllNamed(HomePage.routeName);
      }
    } on DioException catch (error) {
      final detail = error.response?.data is Map<String, dynamic>
          ? error.response?.data['detail']
          : null;
      _message.value = '初始化失败：${detail ?? error.message}';
    } finally {
      if (mounted) {
        _initializing.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('创建管理员账户', style: Theme.of(context).textTheme.titleLarge),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(
                '创建管理员账户',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '服务器未初始化，请设置服务器名称并创建第一个管理员账户。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '服务器地址：${widget.serverUrl}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _serverNameController,
                decoration: const InputDecoration(
                  labelText: '服务器名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '管理员账号',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '管理员密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => FilledButton.icon(
                  onPressed: _initializing.value ? null : _initializeServer,
                  icon: _initializing.value
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.admin_panel_settings),
                  label: Text(_initializing.value ? '正在初始化...' : '初始化服务器'),
                ),
              ),
              Obx(() {
                final message = _message.value;
                if (message == null) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(message),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
