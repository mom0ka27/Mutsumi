import 'package:get/get.dart';

class CurrentUserController extends GetxService {
  final permissionGroup = RxnString();

  bool get isAdmin => permissionGroup.value == 'Admin';

  /// Whether the server would accept `require_download_permission` requests,
  /// which cover both download tasks and subscription management.
  ///
  /// Guest is the only group denied. An unknown group stays permissive — the
  /// server is still the authority, and hiding a control because the cached
  /// group has not arrived yet would be the worse failure.
  bool get canManageDownloads => permissionGroup.value != 'Guest';

  void setPermissionGroup(String value) => permissionGroup.value = value;

  void clear() {
    permissionGroup.value = null;
  }
}
