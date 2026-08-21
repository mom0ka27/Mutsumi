import 'bangumi_repository.dart';

/// Where a show is in its broadcast run.
///
/// Bangumi exposes no status field, so this is derived from dates. It decides
/// which entry point is the right one: subscribing to an unaired show works,
/// downloading it cannot.
enum AiringStatus {
  unaired,
  airing,
  finished,

  /// No first-broadcast date upstream. Nothing is restricted — the server is
  /// the authority on what actually works, and guessing would only take away
  /// options that do.
  unknown;

  bool get canDownload => this != AiringStatus.unaired;

  /// Whether following the show is the action being pushed forward.
  bool get prefersSubscription =>
      this == AiringStatus.unaired || this == AiringStatus.airing;
}

/// Derives the status from the subject's air date plus its episode airdates.
///
/// [airDate] carries the decision for `unaired`, not the episode list: a show
/// that has not started usually has no episode rows at all (measured
/// 2026-08-21: subject 412008 premieres 2026-10-07 and `/v0/episodes` returns
/// zero rows). The episode airdates only separate airing from finished.
AiringStatus deriveAiringStatus({
  required String airDate,
  List<BangumiEpisode> episodes = const [],
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final start = _parseDate(airDate);
  final airdates = episodes
      .map((episode) => _parseDate(episode.airDate))
      .whereType<DateTime>()
      .toList();
  final last = airdates.isEmpty
      ? null
      : airdates.reduce((a, b) => a.isAfter(b) ? a : b);

  if (start == null) {
    if (last != null && !last.isAfter(current)) return AiringStatus.finished;
    return AiringStatus.unknown;
  }
  if (start.isAfter(current)) return AiringStatus.unaired;
  if (last == null) {
    // Started, but no usable episode dates — common for older shows. Calling
    // that "airing" only leaves an extra entry point around, while calling it
    // "unaired" would disable a download that does work.
    return AiringStatus.finished;
  }
  return last.isAfter(current) ? AiringStatus.airing : AiringStatus.finished;
}

DateTime? _parseDate(String value) {
  final text = value.trim();
  if (text.length < 10) return null;
  return DateTime.tryParse(text.substring(0, 10));
}
