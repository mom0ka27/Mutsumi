import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mutsumi/constants.dart';
import '../../../core/extensions/build_context.dart';

import '../../../core/widgets/app_glass_background.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_glass_settings.dart';
import '../data/users_repository.dart';
import 'users_management_controller.dart';

class UsersManagementPage extends GetView<UsersManagementController> {
  const UsersManagementPage({super.key});

  Future<void> _edit([ManagedUser? user]) async {
    controller.beginEdit(user);
    await showAppDialog<void>(
      _UserEditDialog(controller: controller, user: user),
    );
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
      await controller.delete(user);
    }
  }

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
        if (controller.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView.separated(
            padding: context.pageContentPadding(horizontal: 16, bottom: 16),
            itemCount: controller.users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final user = controller.users[index];
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

class _UserEditDialog extends StatefulWidget {
  const _UserEditDialog({required this.controller, required this.user});

  final UsersManagementController controller;
  final ManagedUser? user;

  @override
  State<_UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<_UserEditDialog> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await widget.controller.save();
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) AppDialog.dismiss(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AlertDialog(
      title: Text(widget.user == null ? '新增用户' : '编辑用户'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller.usernameController,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            TextField(
              controller: controller.passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.user == null ? '密码' : '新密码（留空不修改）',
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => DropdownButtonFormField<String>(
                initialValue: controller.permissionGroup.value,
                decoration: const InputDecoration(labelText: '权限组'),
                items: const ['Admin', 'User', 'Guest']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.permissionGroup.value = value;
                        }
                      },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => AppDialog.dismiss(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中...' : '保存'),
        ),
      ],
    );
  }
}
