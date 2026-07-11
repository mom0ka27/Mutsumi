import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../data/users_repository.dart';

class UsersManagementPage extends StatefulWidget {
  const UsersManagementPage({super.key});

  @override
  State<UsersManagementPage> createState() => _UsersManagementPageState();
}

class _UsersManagementPageState extends State<UsersManagementPage> {
  final _repository = UsersRepository();
  final _users = <ManagedUser>[].obs;
  final _loading = true.obs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    try {
      _users.assignAll(await _repository.listUsers());
    } catch (error) {
      Get.snackbar('加载失败', error.toString());
    } finally {
      _loading.value = false;
    }
  }

  Future<void> _edit([ManagedUser? user]) async {
    final username = TextEditingController(text: user?.username);
    final password = TextEditingController();
    final permission = (user?.permissionGroup ?? 'User').obs;
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text(user == null ? '新增用户' : '编辑用户'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: username,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: user == null ? '密码' : '新密码（留空不修改）',
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => DropdownButtonFormField<String>(
                  initialValue: permission.value,
                  decoration: const InputDecoration(labelText: '权限组'),
                  items: const ['Admin', 'User', 'Guest']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) permission.value = value;
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        username.text.trim().isNotEmpty &&
        (user != null || password.text.isNotEmpty)) {
      if (user == null) {
        await _repository.createUser(
          username: username.text.trim(),
          password: password.text,
          permissionGroup: permission.value,
        );
      } else {
        await _repository.updateUser(
          user.id,
          username: username.text.trim(),
          permissionGroup: permission.value,
          password: password.text,
        );
      }
      await _load();
    }
    username.dispose();
    password.dispose();
  }

  Future<void> _delete(ManagedUser user) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('删除用户'),
        content: Text('确定删除“${user.username}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repository.deleteUser(user.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassPage(
      enableBackgroundSampling: false,
      background: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primaryContainer.withValues(alpha: 0.72),
              colors.surface,
              colors.secondaryContainer.withValues(alpha: 0.72),
            ],
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('用户管理'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _edit,
          child: const Icon(Icons.person_add_rounded),
        ),
        body: Obx(() {
          if (_loading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final user = _users[index];
                final colors = Theme.of(context).colorScheme;
                return GlassCard(
                  useOwnLayer: true,
                  padding: EdgeInsets.zero,
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: Constants.radius.x,
                  ),
                  settings: LiquidGlassSettings.figma(
                    refraction: 36,
                    depth: 20,
                    dispersion: 6,
                    frost: 4,
                    glassColor: colors.surface.withValues(alpha: 0.28),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      child: Icon(
                        Icons.person_rounded,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    title: Text(user.username),
                    subtitle: Text(user.permissionGroup),
                    onTap: () => _edit(user),
                    trailing: IconButton(
                      onPressed: () => _delete(user),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}
