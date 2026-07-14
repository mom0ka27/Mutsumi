import 'package:get/get.dart';

class CurrentUserController extends GetxService {
  final permissionGroup = RxnString();

  bool get isAdmin => permissionGroup.value == 'Admin';

  void setPermissionGroup(String value) => permissionGroup.value = value;

  void clear() {
    permissionGroup.value = null;
  }
}
