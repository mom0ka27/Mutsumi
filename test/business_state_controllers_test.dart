import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:mutsumi/features/downloads/data/download_repository.dart';
import 'package:mutsumi/features/downloads/presentation/download_progress_controller.dart';
import 'package:mutsumi/features/auth/presentation/current_user_controller.dart';
import 'package:mutsumi/features/settings/data/settings_repository.dart';
import 'package:mutsumi/features/settings/presentation/qbittorrent_settings_controller.dart';
import 'package:mutsumi/features/settings/presentation/saved_servers_binding.dart';
import 'package:mutsumi/features/settings/presentation/saved_servers_controller.dart';
import 'package:mutsumi/features/settings/presentation/settings_home_binding.dart';
import 'package:mutsumi/features/settings/presentation/settings_home_controller.dart';
import 'package:mutsumi/features/settings/presentation/storage_status_controller.dart';

void main() {
  tearDown(Get.reset);

  group('DownloadProgressController', () {
    final downloading = _task(hash: 'a', state: 'downloading', progress: 0.5);
    final completed = _task(hash: 'b', state: 'uploading', progress: 1);

    test('按下载状态筛选任务', () {
      final controller = DownloadProgressController();
      controller.tasks.assignAll([downloading, completed]);

      expect(controller.filteredTasks, [downloading]);

      controller.setFilter(DownloadFilter.completed);

      expect(controller.filteredTasks, [completed]);
    });

    test('识别暂停和完成状态', () {
      final controller = DownloadProgressController();
      final paused = _task(hash: 'c', state: 'stoppedDL', progress: 0.2);

      expect(controller.isPaused(paused), isTrue);
      expect(controller.isCompleted(paused), isFalse);
      expect(controller.isCompleted(completed), isTrue);
    });

    test('关闭后忽略尚未完成的任务加载', () async {
      final repository = _PendingDownloadRepository();
      final controller = Get.put(
        DownloadProgressController(repository: repository),
      );
      final loading = controller.loadTasks();

      await Get.delete<DownloadProgressController>(force: true);
      repository.complete([downloading]);
      await loading;

      expect(controller.tasks, isEmpty);
      expect(controller.loading.value, isTrue);
      expect(controller.error.value, isNull);
    });
  });

  test('StorageStatus 解析服务端存储状态', () {
    final status = StorageStatus.fromJson({
      'data_path': '/data',
      'data_size_bytes': 1024,
      'data_file_count': 2,
      'disk_total_bytes': 4096,
      'disk_used_bytes': 1024,
      'disk_free_bytes': 3072,
      'anime': [
        {
          'name': 'Anime',
          'size_bytes': 512,
          'file_count': 1,
          'download_hash': 'hash',
        },
      ],
    });

    expect(status.dataPath, '/data');
    expect(status.diskFreeBytes, 3072);
    expect(status.anime.single.name, 'Anime');
    expect(status.anime.single.downloadHash, 'hash');
  });

  test('QBittorrentSettingsController 格式化分享率', () {
    final controller = QBittorrentSettingsController();

    controller.setShareRatio(3.4);
    expect(controller.ratioLabel, '3.4');

    controller.setShareRatio(10);
    expect(controller.ratioLabel, '无限');
  });

  test('SavedServersBinding 注册业务控制器', () {
    Get.put(SettingsRepository());
    SavedServersBinding().dependencies();

    expect(Get.find<SavedServersController>(), isA<SavedServersController>());
  });

  test('SettingsHomeBinding 注册业务控制器', () {
    Get.put(CurrentUserController());
    Get.put(SettingsRepository());
    SettingsHomeBinding().dependencies();

    expect(Get.find<SettingsHomeController>(), isA<SettingsHomeController>());
  });
}

DownloadTask _task({
  required String hash,
  required String state,
  required double progress,
}) => DownloadTask(
  hash: hash,
  name: hash,
  state: state,
  progress: progress,
  totalSize: 100,
  downloaded: 50,
  downloadSpeed: 10,
  uploadSpeed: 0,
  eta: 5,
);

class _PendingDownloadRepository extends DownloadRepository {
  final _tasks = Completer<List<DownloadTask>>();

  @override
  Future<List<DownloadTask>> listTasks() => _tasks.future;

  void complete(List<DownloadTask> tasks) => _tasks.complete(tasks);
}
