import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

class LocalStorage {
  static const settingsBoxName = 'settings';
  static const dandanPlayBoxName = 'dandanplay';
  static late final String applicationSupportPath;

  static Future<void> init() async {
    final directory = await getApplicationSupportDirectory();
    applicationSupportPath = directory.path;
    Hive.init(directory.path);
    await Hive.openBox(settingsBoxName);
    await Hive.openBox(dandanPlayBoxName);
  }
}
