import 'package:flutter_test/flutter_test.dart';

import 'package:mutsumi/features/bangumi/data/airing_status.dart';
import 'package:mutsumi/features/bangumi/data/bangumi_repository.dart';

void main() {
  final now = DateTime.parse('2026-08-21T12:00:00');

  AiringStatus statusOf(String airDate, List<String> airdates) =>
      deriveAiringStatus(
        airDate: airDate,
        episodes: [
          for (var index = 0; index < airdates.length; index++)
            BangumiEpisode(
              index: index + 1,
              name: '',
              nameCn: '',
              airDate: airdates[index],
            ),
        ],
        now: now,
      );

  group('deriveAiringStatus', () {
    test('未开播的番通常没有集数表，不能因此判成已完结', () {
      // 实测 2026-08-21：subject 412008 首播 2026-10-07，/v0/episodes 返回 0 条。
      expect(statusOf('2026-10-07', const []), AiringStatus.unaired);
      expect(statusOf('2026-10-09', const ['']), AiringStatus.unaired);
    });

    test('末集尚未播出为连载中，已播完为已完结', () {
      expect(
        statusOf('2026-08-12', const ['2026-08-12', '2026-09-30']),
        AiringStatus.airing,
      );
      expect(
        statusOf('2023-09-29', const ['2023-09-29', '2024-03-22']),
        AiringStatus.finished,
      );
    });

    test('老番缺 airdate 时按已完结处理，不禁用本可用的下载', () {
      expect(statusOf('2015-01-01', const []), AiringStatus.finished);
    });

    test('没有首播日则不猜，只有末集日期能单独证明已完结', () {
      expect(statusOf('', const []), AiringStatus.unknown);
      expect(statusOf('', const ['2024-03-22']), AiringStatus.finished);
    });
  });

  group('入口按钮的取舍', () {
    test('只有未开播禁用下载', () {
      expect(AiringStatus.unaired.canDownload, isFalse);
      for (final status in [
        AiringStatus.airing,
        AiringStatus.finished,
        AiringStatus.unknown,
      ]) {
        expect(status.canDownload, isTrue, reason: status.name);
      }
    });

    test('未开播和连载中以追番为主，已完结和未知以下载为主', () {
      expect(AiringStatus.unaired.prefersSubscription, isTrue);
      expect(AiringStatus.airing.prefersSubscription, isTrue);
      expect(AiringStatus.finished.prefersSubscription, isFalse);
      expect(AiringStatus.unknown.prefersSubscription, isFalse);
    });
  });
}
