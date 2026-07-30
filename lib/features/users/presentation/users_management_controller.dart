import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/users_repository.dart';

class UsersManagementController extends GetxController {
  UsersManagementController({UsersRepository? repository})
    : _repository = repository ?? UsersRepository();

  final UsersRepository _repository;
  final users = <ManagedUser>[].obs;
  final loading = true.obs;
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final permissionGroup = 'User'.obs;
  ManagedUser? editingUser;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    try {
      final loadedUsers = await _repository.listUsers();
      if (isClosed) return;
      users.assignAll(loadedUsers);
    } catch (error) {
      if (isClosed) return;
      await showErrorDialog(
        title: '加载失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (!isClosed) {
        loading.value = false;
      }
    }
  }

  void beginEdit([ManagedUser? user]) {
    editingUser = user;
    usernameController.text = user?.username ?? '';
    passwordController.clear();
    permissionGroup.value = user?.permissionGroup ?? 'User';
  }

  String? validateUserInput() {
    if (usernameController.text.trim().isEmpty) {
      return '请输入用户名。';
    }
    if (editingUser == null && passwordController.text.isEmpty) {
      return '请输入密码。';
    }
    return null;
  }

  Future<bool> save() async {
    final validationMessage = validateUserInput();
    if (validationMessage != null) {
      await showErrorDialog(title: '无法保存', message: validationMessage);
      return false;
    }

    final user = editingUser;
    final username = usernameController.text.trim();
    final password = passwordController.text;
    try {
      if (user == null) {
        await _repository.createUser(
          username: username,
          password: password,
          permissionGroup: permissionGroup.value,
        );
      } else {
        await _repository.updateUser(
          user.id,
          username: username,
          permissionGroup: permissionGroup.value,
          password: password,
        );
      }
      await load();
      if (isClosed) return false;
      await showInfoDialog(title: '保存成功', message: '用户信息已更新');
      return true;
    } catch (error) {
      await showErrorDialog(
        title: '保存失败',
        message: errorMessageOf(error),
        error: error,
      );
      return false;
    }
  }

  Future<void> delete(ManagedUser user) async {
    try {
      await _repository.deleteUser(user.id);
      await load();
      if (isClosed) return;
      await showInfoDialog(title: '删除成功', message: '用户已删除');
    } catch (error) {
      await showErrorDialog(
        title: '删除失败',
        message: errorMessageOf(error),
        error: error,
      );
    }
  }

  @override
  void onClose() {
    usernameController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
