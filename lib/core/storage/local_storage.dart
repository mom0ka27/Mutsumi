import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/settings/data/settings_repository.dart';

class LocalStorage {
  static const settingsBoxName = 'settings';

  static Future<void> init() async {
    final directory = await getApplicationSupportDirectory();
    Hive.init(directory.path);
    await Hive.openBox(settingsBoxName);
    await SettingsRepository.migrate();
  }
}
