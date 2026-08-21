import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mutsumi/features/subscriptions/data/subscription_models.dart';
import 'package:mutsumi/features/subscriptions/presentation/following_section.dart';

void main() {
  SubscriptionRead subscription(Map<String, dynamic> overrides) =>
      SubscriptionRead.fromJson({
        'id': 1,
        'anime_id': 7,
        'bangumi_id': 4242,
        'anime_name': 'Test Anime',
        'anime_name_cn': '测试番剧',
        'image_url': '',
        'enabled': true,
        'episode_count': 12,
        ...overrides,
      });

  Future<void> pump(WidgetTester tester, SubscriptionRead item) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FollowingSection(
              subscriptions: [item],
              onChanged: () async {},
            ),
          ),
        ),
      );

  testWidgets('标题和数量', (tester) async {
    await pump(tester, subscription({}));

    expect(find.text('追番中'), findsOne);
    expect(find.text('测试番剧'), findsOne);
  });

  testWidgets('待确认优先于其他状态，包括失败', (tester) async {
    await pump(
      tester,
      subscription({
        'needs_review_count': 2,
        'last_error': 'boom',
        'next_episode_index': 3,
      }),
    );

    expect(find.text('2 集待确认'), findsOne);
  });

  testWidgets('暂停的订阅只说已暂停', (tester) async {
    await pump(
      tester,
      subscription({'enabled': false, 'needs_review_count': 2}),
    );

    expect(find.text('已暂停'), findsOne);
  });

  testWidgets('尚未播出的下一集显示日期', (tester) async {
    final airDate = DateTime.now().add(const Duration(days: 5));
    await pump(
      tester,
      subscription({
        'next_episode_index': 3,
        'next_episode_air_date': airDate.toIso8601String(),
      }),
    );

    expect(find.text('第 3 集 · ${airDate.month}/${airDate.day}'), findsOne);
  });

  testWidgets('已播出但仍缺的集说明在等资源', (tester) async {
    await pump(
      tester,
      subscription({
        'next_episode_index': 3,
        'next_episode_air_date': DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
      }),
    );

    expect(find.text('第 3 集 · 等待资源'), findsOne);
  });

  testWidgets('没有缺集时报已补齐', (tester) async {
    await pump(tester, subscription({'owned_episode_count': 12}));

    expect(find.text('已补齐 12 集'), findsOne);
  });

  testWidgets('检查失败在没有待确认时才显示', (tester) async {
    await pump(tester, subscription({'last_error': 'boom'}));

    expect(find.text('上次检查失败'), findsOne);
  });
}
