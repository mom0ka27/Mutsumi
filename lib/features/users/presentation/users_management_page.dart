import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/network/app_network_error.dart';
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
      await showErrorDialog(
        title: '加载失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      _loading.value = false;
    }
  }

  Future<void> _edit([ManagedUser? user]) async {
    final username = TextEditingController(text: user?.username);
    final password = TextEditingController();
    final permission = (user?.permissionGroup ?? 'User').obs;
    final confirmed = await showAppDialog<bool>(
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
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AppDialog.dismiss(context, false),
              child: const Text('取消'),
            ),
          ),
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppDialog.dismiss(context, true),
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        username.text.trim().isNotEmpty &&
        (user != null || password.text.isNotEmpty)) {
      try {
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
        await showInfoDialog(title: '保存成功', message: '用户信息已更新');
      } catch (error) {
        await showErrorDialog(
          title: '保存失败',
          message: errorMessageOf(error),
          error: error,
        );
      }
    }
    username.dispose();
    password.dispose();
  }

  Future<void> _delete(ManagedUser user) async {
    final confirmed = await showAppDialog<bool>(
      AlertDialog(
        title: const Text('删除用户'),
        content: Text('确定删除“${user.username}”吗？'),
        actions: [
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AppDialog.dismiss(context, false),
              child: const Text('取消'),
            ),
          ),
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppDialog.dismiss(context, true),
              child: const Text('删除'),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _repository.deleteUser(user.id);
        await _load();
        await showInfoDialog(title: '删除成功', message: '用户已删除');
      } catch (error) {
        await showErrorDialog(
          title: '删除失败',
          message: errorMessageOf(error),
          error: error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      enableBackgroundSampling: true,
      extendBody: true,
      background: const AppGlassBackground(),
      appBar: GlassAppBar(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('用户管理', style: Theme.of(context).textTheme.titleLarge),
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
            padding: const EdgeInsets.fromLTRB(
              16,
              Constants.topPadding,
              16,
              16,
            ),
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
                settings: AppGlassSettings.standard(context),
                child: Material(
                  color: Colors.transparent,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.all(Constants.radius),
                  ),
                  clipBehavior: Clip.antiAlias,
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
                ),
              );
            },
          ),
        );
      }),
    );
  }
}
