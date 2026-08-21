import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_paths.dart';
import '../../settings/data/authenticated_server_client.dart';
import 'subscription_models.dart';

class SubscriptionService {
  SubscriptionService({AuthenticatedServerClient? serverClient})
    : _serverClient = serverClient ?? AuthenticatedServerClient();

  final AuthenticatedServerClient _serverClient;

  Future<List<PreferenceProfileRead>> listProfiles() async {
    return _request('获取订阅偏好', () async {
      final response = await _serverClient.dio.get<List<dynamic>>(
        preferenceProfilesApiPath,
      );
      return (response.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PreferenceProfileRead.fromJson)
          .toList();
    });
  }

  Future<List<SubscriptionRead>> listSubscriptions() async {
    return _request('获取追番订阅', () async {
      final response = await _serverClient.dio.get<List<dynamic>>(
        subscriptionsApiPath,
      );
      return (response.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SubscriptionRead.fromJson)
          .toList();
    });
  }

  Future<List<FansubCandidateRead>> listFansubs(int bangumiId) async {
    return _request('获取字幕组候选', () async {
      final response = await _serverClient.dio.get<List<dynamic>>(
        '$subscriptionsApiPath/fansubs',
        queryParameters: {'bangumi_id': bangumiId},
      );
      return (response.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FansubCandidateRead.fromJson)
          .toList();
    });
  }

  Future<SubscriptionRead> createSubscription({
    required int animeId,
    required int profileId,
    required List<String> fansubs,
    required bool allowNoFansub,
  }) async {
    return _request('创建追番订阅', () async {
      final response = await _serverClient.dio.post<Map<String, dynamic>>(
        subscriptionsApiPath,
        data: _subscriptionPayload(
          animeId: animeId,
          profileId: profileId,
          fansubs: fansubs,
          allowNoFansub: allowNoFansub,
        ),
      );
      return _parseSubscription(response.data);
    });
  }

  Future<SubscriptionRead> updateSubscription({
    required int subscriptionId,
    required int profileId,
    required List<String> fansubs,
    required bool allowNoFansub,
    required bool enabled,
  }) async {
    return _request('更新追番订阅', () async {
      final response = await _serverClient.dio.put<Map<String, dynamic>>(
        '$subscriptionsApiPath/$subscriptionId',
        data: {
          'profile_id': profileId,
          'fansubs': fansubs,
          'allow_no_fansub': allowNoFansub,
          'enabled': enabled,
        },
      );
      return _parseSubscription(response.data);
    });
  }

  Future<void> deleteSubscription(int subscriptionId) async {
    await _request('删除追番订阅', () {
      return _serverClient.dio.delete<void>(
        '$subscriptionsApiPath/$subscriptionId',
      );
    });
  }

  Future<SubscriptionPreviewRead> previewSubscription({
    required int animeId,
    required int profileId,
    required List<String> fansubs,
    required bool allowNoFansub,
  }) async {
    return _request('预览追番规则', () async {
      final response = await _serverClient.dio.post<Map<String, dynamic>>(
        '$subscriptionsApiPath/preview',
        data: _subscriptionPayload(
          animeId: animeId,
          profileId: profileId,
          fansubs: fansubs,
          allowNoFansub: allowNoFansub,
        ),
      );
      final data = response.data;
      if (data == null) {
        throw StateError('服务器返回了空的订阅预览');
      }
      return SubscriptionPreviewRead.fromJson(data);
    });
  }

  Map<String, dynamic> _subscriptionPayload({
    required int animeId,
    required int profileId,
    required List<String> fansubs,
    required bool allowNoFansub,
  }) {
    return {
      'anime_id': animeId,
      'profile_id': profileId,
      'fansubs': fansubs,
      'allow_no_fansub': allowNoFansub,
      'use_subject_id': true,
      'resource_types': ['动画'],
    };
  }

  SubscriptionRead _parseSubscription(Map<String, dynamic>? data) {
    if (data == null) {
      throw StateError('服务器返回了空的订阅');
    }
    return SubscriptionRead.fromJson(data);
  }

  Future<T> _request<T>(String operation, Future<T> Function() request) async {
    try {
      return await request();
    } catch (error, stackTrace) {
      AppLogger.error(
        '$operation失败',
        tag: 'Subscription',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
