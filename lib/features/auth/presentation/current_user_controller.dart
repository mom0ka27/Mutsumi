import 'package:get/get.dart';

class CurrentUserController extends GetxService {
  static CurrentUserController get instance {
    if (Get.isRegistered<CurrentUserController>()) {
      return Get.find<CurrentUserController>();
    }
    return Get.put(CurrentUserController(), permanent: true);
  }

  final permissionGroup = RxnString();

  bool get isAdmin => permissionGroup.value == 'Admin';

  void setPermissionGroup(String value) => permissionGroup.value = value;

  void clear() {
    permissionGroup.value = null;
  }
}
