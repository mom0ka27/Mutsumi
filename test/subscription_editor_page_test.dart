import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

import 'package:mutsumi/core/storage/local_storage.dart';
import 'package:mutsumi/core/widgets/app_glass_background.dart';
import 'package:mutsumi/features/bangumi/data/airing_status.dart';
import 'package:mutsumi/features/subscriptions/data/subscription_models.dart';
import 'package:mutsumi/features/subscriptions/data/subscription_service.dart';
import 'package:mutsumi/features/subscriptions/presentation/subscription_editor_page.dart';

void main() {
  // The page sits on the glass background, which reads the appearance settings.
  setUpAll(() async {
    Hive.init('.test_hive/subscription_editor');
    await Hive.openBox(LocalStorage.settingsBoxName);
  });

  tearDownAll(() async {
    await Get.deleteAll(force: true);
    await Hive.deleteBoxFromDisk(LocalStorage.settingsBoxName);
    await Hive.close();
  });

  setUp(() {
    Get.reset();
    Get.put(AppearanceController(), permanent: true);
  });

  SubscriptionPreviewRead preview({
    int episodeCount = 12,
    int airedEpisodeCount = 6,
    List<int> matched = const [1, 2, 3, 4, 5],
    List<int> missing = const [6],
  }) => SubscriptionPreviewRead.fromJson({
    'resource_count': 40,
    'accepted_count': 9,
    'episode_count': episodeCount,
    'aired_episode_count': airedEpisodeCount,
    'owned_episode_count': 0,
    'matched_episodes': matched,
    'missing_episodes': missing,
    'candidates': const [],
  });

  Future<_FakeSubscriptionService> pump(
    WidgetTester tester, {
    SubscriptionPreviewRead? result,
    AiringStatus status = AiringStatus.airing,
  }) async {
    // Tall enough that every fansub row and the floating save bar coexist
    // without scrolling, so taps land on the row and not on the bar.
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _FakeSubscriptionService(result ?? preview());
    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionEditorPage(
          bangumiId: 4242,
          title: '测试番剧',
          status: status,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  // The locked group's name also shows in the save bar, so the tile has to be
  // addressed by its row rather than by its label.
  Finder fansubTile(String name) => find.ancestor(
    of: find.text(name),
    matching: find.byType(RadioListTile<String>),
  );

  Future<void> tapFansub(WidgetTester tester, String name) async {
    await tester.tap(fansubTile(name));
    await tester.pumpAndSettle();
  }

  testWidgets('打开就查询已播出的集，不用先按按钮', (tester) async {
    final service = await pump(tester);

    expect(service.previewCalls, 1);
    // A show already airing defaults to catching up, so the first query has to
    // span the season rather than the cold-start window.
    expect(service.lastBackfillAired, isTrue);
    expect(find.text('已播出 6 集 · 共 12 集'), findsOne);
    expect(find.text('将下载 5 集：1-5'), findsOne);
  });

  testWidgets('已播出但没匹配到的集单独点出来', (tester) async {
    await pump(tester);

    expect(find.text('第 6 集已播出但没有匹配到资源'), findsOne);
  });

  testWidgets('一集都没匹配到时说清楚是规则的问题', (tester) async {
    await pump(
      tester,
      result: preview(matched: const [], missing: const [1, 2, 3, 4, 5, 6]),
    );

    expect(find.text('已播出 6 集 · 共 12 集'), findsOne);
    expect(find.text('当前规则没有匹配到任何一集'), findsOne);
    expect(find.text('第 1-6 集已播出但没有匹配到资源'), findsOne);
  });

  testWidgets('默认锁定资源最多的字幕组，整季只跟它', (tester) async {
    final service = await pump(tester);

    expect(service.lastFansub, 'ANi');
    expect(find.text('整季只跟 ANi'), findsOne);
    // Single lock, not a priority list: exactly one radio is on.
    final selected = tester
        .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
        .where((tile) => tile.value == 'ANi');
    expect(selected.length, 1);
    expect(find.text('ANi · 立即下载 5 集'), findsOne);
  });

  testWidgets('换字幕组要重新匹配，再点一次可以解除锁定', (tester) async {
    await pump(tester);

    await tapFansub(tester, '喵萌奶茶屋');
    expect(find.text('整季只跟 喵萌奶茶屋'), findsOne);
    expect(find.text('规则已改，重新匹配'), findsOne);

    await tapFansub(tester, '喵萌奶茶屋');
    expect(find.text('整季只跟一个字幕组'), findsOne);
    expect(find.text('未锁定字幕组'), findsOne);
  });

  testWidgets('改了字幕组后已播出集数还在，匹配结果标为过期', (tester) async {
    await pump(tester);

    await tapFansub(tester, '喵萌奶茶屋');

    // Rule-independent, so it stays: it is what tells the user whether an empty
    // match means "nothing aired" or "rules too narrow".
    expect(find.text('已播出 6 集 · 共 12 集'), findsOne);
    expect(find.text('将下载 5 集：1-5'), findsNothing);
    expect(find.text('规则已改，重新匹配'), findsOne);
  });

  testWidgets('未播出的番剧不提补齐，也不按整季查询', (tester) async {
    final service = await pump(
      tester,
      status: AiringStatus.unaired,
      result: preview(
        airedEpisodeCount: 0,
        matched: const [],
        missing: const [],
      ),
    );

    expect(service.lastBackfillAired, isFalse);
    expect(find.text('补齐已播出的集'), findsNothing);
    expect(find.text('还没有开播 · 共 12 集'), findsOne);
  });
}

class _FakeSubscriptionService extends SubscriptionService {
  _FakeSubscriptionService(this.result);

  final SubscriptionPreviewRead result;
  int previewCalls = 0;
  bool? lastBackfillAired;
  String? lastFansub;

  @override
  Future<List<PreferenceProfileRead>> listProfiles() async => [
    PreferenceProfileRead.fromJson({
      'id': 1,
      'name': '默认',
      'is_default': true,
    }),
  ];

  // Server-side order: most prolific group first.
  @override
  Future<List<FansubCandidateRead>> listFansubs(int bangumiId) async => [
    FansubCandidateRead.fromJson({'name': 'ANi', 'count': 12}),
    FansubCandidateRead.fromJson({'name': '喵萌奶茶屋', 'count': 5}),
    FansubCandidateRead.fromJson({
      'name': '(无字幕组)',
      'count': 2,
      'is_no_fansub': true,
    }),
  ];

  @override
  Future<SubscriptionPreviewRead> previewSubscription({
    required int bangumiId,
    required int profileId,
    required String fansub,
    required bool allowNoFansub,
    bool backfillAired = false,
  }) async {
    previewCalls++;
    lastBackfillAired = backfillAired;
    lastFansub = fansub;
    return result;
  }
}
