import 'package:get/get.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/app_network_error.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../auth/presentation/current_user_controller.dart';
import '../../subscriptions/data/subscription_models.dart';
import '../../subscriptions/data/subscription_store.dart';
import '../data/airing_status.dart';
import '../data/bangumi_repository.dart';

class BangumiDetailController extends GetxController {
  BangumiDetailController({
    required this.subject,
    BangumiRepository? repository,
    SubscriptionStore? subscriptionStore,
    CurrentUserController? currentUserController,
  }) : _repository = repository ?? BangumiRepository(),
       _subscriptionStore = subscriptionStore ?? SubscriptionStore(),
       _currentUser = currentUserController ?? CurrentUserController();

  final BangumiSubject subject;
  final BangumiRepository _repository;
  final SubscriptionStore _subscriptionStore;
  final CurrentUserController _currentUser;
  final detail = Rxn<BangumiSubjectDetail>();
  final loading = true.obs;
  final status = AiringStatus.unknown.obs;
  final subscription = Rxn<SubscriptionRead>();

  bool get canSubscribe => _currentUser.canManageDownloads;

  @override
  void onInit() {
    super.onInit();
    if (subject is BangumiSubjectDetail) {
      detail.value = subject as BangumiSubjectDetail;
    }
    loadDetail();
    loadAiringStatus();
    loadSubscription();
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

  /// Bangumi has no status field, so it comes from the episode airdates.
  ///
  /// Failure leaves the status `unknown`, which restricts nothing — a network
  /// hiccup must not take away the download button.
  Future<void> loadAiringStatus() async {
    try {
      final episodes = await _repository.getMainEpisodes(subject.id);
      if (isClosed) return;
      status.value = deriveAiringStatus(
        airDate: subject.airDate,
        episodes: episodes,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        '推导放送状态失败 subject=${subject.id}',
        tag: 'Bangumi',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> loadSubscription() async {
    if (!canSubscribe) return;
    // The shared store backs the home "追番中" section too, so following a show
    // here shows up there right away.
    await _subscriptionStore.refresh();
    if (isClosed) return;
    subscription.value = _subscriptionStore.forBangumi(subject.id);
  }
}
