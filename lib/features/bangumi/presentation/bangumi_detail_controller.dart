import 'package:get/get.dart';

import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/bangumi_repository.dart';

class BangumiDetailController extends GetxController {
  BangumiDetailController({
    required this.subject,
    BangumiRepository? repository,
  }) : _repository = repository ?? BangumiRepository();

  final BangumiSubject subject;
  final BangumiRepository _repository;
  final detail = Rxn<BangumiSubjectDetail>();
  final loading = true.obs;

  @override
  void onInit() {
    super.onInit();
    if (subject is BangumiSubjectDetail) {
      detail.value = subject as BangumiSubjectDetail;
    }
    loadDetail();
  }

  Future<void> loadDetail() async {
    loading.value = true;
    try {
      final loadedDetail = await _repository.getSubjectDetail(subject.id);
      if (isClosed) return;
      detail.value = loadedDetail;
    } catch (error) {
      if (isClosed) return;
      await showErrorDialog(
        title: '详情加载失败',
        message: errorMessageOf(error),
        error: error,
      );
    } finally {
      if (!isClosed) {
        loading.value = false;
      }
    }
  }
}
