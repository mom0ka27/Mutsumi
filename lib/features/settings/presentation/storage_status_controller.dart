import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/authenticated_server_client.dart';

class StorageStatusController extends GetxController {
  StorageStatusController({AuthenticatedServerClient? client})
    : _client = client ?? AuthenticatedServerClient();

  final AuthenticatedServerClient _client;
  final loading = true.obs;
  final forbidden = false.obs;
  final errorMessage = RxnString();
  final status = Rxn<StorageStatus>();
  var _showingError = false;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({bool refresh = false}) async {
    loading.value = true;
    errorMessage.value = null;
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        storageApiPath,
        queryParameters: refresh ? const {'refresh': true} : null,
      );
      if (isClosed || response.data == null) return;
      status.value = StorageStatus.fromJson(response.data!);
      forbidden.value = false;
    } on DioException catch (error) {
      if (isClosed) return;
      if (error.response?.statusCode == 403) {
        forbidden.value = true;
      } else {
        errorMessage.value = errorMessageOf(error);
        await _showErrorDialog(error);
      }
    } catch (error) {
      if (isClosed) return;
      errorMessage.value = errorMessageOf(error);
      await _showErrorDialog(error);
    } finally {
      if (!isClosed) loading.value = false;
    }
  }

  Future<void> _showErrorDialog(Object error) async {
    if (_showingError || isClosed) return;
    _showingError = true;
    await showErrorDialog(
      title: '加载存储信息失败',
      message: errorMessageOf(error),
      error: error,
    );
    _showingError = false;
  }
}

class StorageStatus {
  const StorageStatus({
    required this.dataPath,
    required this.dataSizeBytes,
    required this.dataFileCount,
    required this.diskTotalBytes,
    required this.diskUsedBytes,
    required this.diskFreeBytes,
    required this.anime,
  });

  factory StorageStatus.fromJson(Map<String, dynamic> json) => StorageStatus(
    dataPath: json['data_path'] as String? ?? '',
    dataSizeBytes: (json['data_size_bytes'] as num?)?.toInt() ?? 0,
    dataFileCount: (json['data_file_count'] as num?)?.toInt() ?? 0,
    diskTotalBytes: (json['disk_total_bytes'] as num?)?.toInt() ?? 0,
    diskUsedBytes: (json['disk_used_bytes'] as num?)?.toInt() ?? 0,
    diskFreeBytes: (json['disk_free_bytes'] as num?)?.toInt() ?? 0,
    anime: (json['anime'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AnimeStorage.fromJson)
        .toList(),
  );

  final String dataPath;
  final int dataSizeBytes;
  final int dataFileCount;
  final int diskTotalBytes;
  final int diskUsedBytes;
  final int diskFreeBytes;
  final List<AnimeStorage> anime;
}

class AnimeStorage {
  const AnimeStorage({
    required this.name,
    required this.sizeBytes,
    required this.fileCount,
    required this.downloadHash,
  });

  factory AnimeStorage.fromJson(Map<String, dynamic> json) => AnimeStorage(
    name: json['name'] as String? ?? '',
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
    downloadHash: json['download_hash'] as String?,
  );

  final String name;
  final int sizeBytes;
  final int fileCount;
  final String? downloadHash;
}
