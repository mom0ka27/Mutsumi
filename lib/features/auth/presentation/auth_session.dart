import '../../settings/data/settings_repository.dart';
import '../data/auth_service.dart';
import 'current_user_controller.dart';

class AuthSession {
  AuthSession({
    SettingsRepository? settingsRepository,
    CurrentUserController? currentUserController,
  }) : _settingsRepository = settingsRepository ?? SettingsRepository(),
       _currentUserController =
           currentUserController ?? CurrentUserController();

  final SettingsRepository _settingsRepository;
  final CurrentUserController _currentUserController;

  Future<void> establish({
    required String serverUrl,
    required String username,
    required String password,
    required LoginResult result,
    String? certificateFingerprint,
    String? serverName,
  }) async {
    await _settingsRepository.saveLogin(
      serverUrl: serverUrl,
      username: username,
      password: password,
      accessToken: result.accessToken,
      permissionGroup: result.permissionGroup,
      certificateFingerprint: certificateFingerprint,
      serverName: serverName,
    );
    _currentUserController.setPermissionGroup(result.permissionGroup);
  }
}
