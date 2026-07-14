import 'package:get/get.dart';

import '../../settings/data/settings_repository.dart';
import '../data/auth_service.dart';
import 'current_user_controller.dart';

class AuthSession {
  AuthSession._();

  static Future<void> establish({
    required String serverUrl,
    required String username,
    required String password,
    required LoginResult result,
    String? certificateFingerprint,
    String? serverName,
  }) async {
    await SettingsRepository().saveLogin(
      serverUrl: serverUrl,
      username: username,
      password: password,
      accessToken: result.accessToken,
      permissionGroup: result.permissionGroup,
      certificateFingerprint: certificateFingerprint,
      serverName: serverName,
    );
    Get.find<CurrentUserController>().setPermissionGroup(result.permissionGroup);
  }
}
