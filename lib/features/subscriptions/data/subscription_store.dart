import 'dart:async';

import 'package:get/get.dart';

import '../../../core/logging/app_logger.dart';
import 'subscription_models.dart';
import 'subscription_service.dart';

/// Holds the "追番中" list for the home view.
///
/// Kept apart from [AnimeListStore] on purpose: the library is what exists on
/// disk, subscriptions are what is expected to arrive. They are shown as
/// separate sections and reload independently.
class SubscriptionStore extends GetxController {
  SubscriptionStore({SubscriptionService? service})
    : _service = service ?? SubscriptionService();

  final SubscriptionService _service;
  final subscriptions = <SubscriptionRead>[].obs;
  final isLoading = true.obs;
  Future<void>? _refreshing;

  @override
  void onInit() {
    super.onInit();
    unawaited(refresh());
  }

  SubscriptionRead? forAnime(int animeId) => subscriptions.firstWhereOrNull(
    (subscription) => subscription.animeId == animeId,
  );

  SubscriptionRead? forBangumi(int bangumiId) => subscriptions.firstWhereOrNull(
    (subscription) => subscription.bangumiId == bangumiId,
  );

  @override
  Future<void> refresh() {
    final refreshing = _refreshing;
    if (refreshing != null) return refreshing;
    final operation = _load();
    _refreshing = operation;
    return operation.whenComplete(() {
      if (identical(_refreshing, operation)) _refreshing = null;
    });
  }

  Future<void> _load() async {
    try {
      final loaded = await _service.listSubscriptions();
      if (isClosed) return;
      subscriptions.value = loaded;
    } catch (error, stackTrace) {
      // A failure here must not take over the library view with a dialog; the
      // section simply keeps showing what it had.
      AppLogger.error(
        '加载追番列表失败',
        tag: 'Subscription',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (!isClosed) isLoading.value = false;
    }
  }
}
