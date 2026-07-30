import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/authenticated_server_client.dart';

class QBittorrentSettingsController extends GetxController {
  QBittorrentSettingsController({AuthenticatedServerClient? client})
    : _client = client ?? AuthenticatedServerClient();

  final AuthenticatedServerClient _client;
  final shareRatioSlider = 3.0.obs;
  final loading = true.obs;
  final saving = false.obs;
  final forbidden = false.obs;
  final errorMessage = RxnString();
  Map<String, dynamic>? _config;
  var _showingError = false;

  String get ratioLabel => shareRatioSlider.value >= 10
      ? '无限'
      : shareRatioSlider.value.toStringAsFixed(1);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void setShareRatio(double value) {
    shareRatioSlider.value = value;
  }

  Future<void> load() async {
    loading.value = true;
    errorMessage.value = null;
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        qbittorrentConfigApiPath,
      );
      if (isClosed) return;
      _config = response.data;
      final ratio = ((response.data?['share_ratio_limit'] as num?) ?? 3.0)
          .toDouble();
      shareRatioSlider.value = ratio < 0 ? 10 : ratio.clamp(0, 9.9);
      forbidden.value = false;
    } on DioException catch (error) {
      if (isClosed) return;
      if (error.response?.statusCode == 403) {
        forbidden.value = true;
      } else {
        errorMessage.value = errorMessageOf(error);
        await _showLoadError(error);
      }
    } catch (error) {
      if (isClosed) return;
      errorMessage.value = errorMessageOf(error);
      await _showLoadError(error);
    } finally {
      if (!isClosed) loading.value = false;
    }
  }

  Future<void> save() async {
    if (_config == null) return;
    saving.value = true;
    try {
      await _client.dio.put<void>(
        qbittorrentConfigApiPath,
        data: {
          'url': _config!['url'] ?? '',
          'username': _config!['username'] ?? '',
          'password': null,
          'download_path': _config!['download_path'] ?? '',
          'share_ratio_limit': shareRatioSlider.value >= 10
              ? -1.0
              : shareRatioSlider.value,
        },
      );
      if (!isClosed) {
        await showInfoDialog(title: '保存成功', message: '分享率限制已保存');
      }
    } on DioException catch (error) {
      if (isClosed) return;
      if (error.response?.statusCode == 403) {
        forbidden.value = true;
      } else {
        await _showSaveError(error);
      }
    } catch (error) {
      if (isClosed) return;
      await _showSaveError(error);
    } finally {
      if (!isClosed) saving.value = false;
    }
  }

  Future<void> _showLoadError(Object error) async {
    if (_showingError || isClosed) return;
    _showingError = true;
    await showErrorDialog(
      title: '加载设置失败',
      message: errorMessageOf(error),
      error: error,
    );
    _showingError = false;
  }

  Future<void> _showSaveError(Object error) => showErrorDialog(
    title: '保存失败',
    message: errorMessageOf(error),
    error: error,
  );
}
