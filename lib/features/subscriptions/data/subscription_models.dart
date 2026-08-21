class PreferenceProfileRead {
  const PreferenceProfileRead({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.languageMode,
    required this.languageUnknown,
    required this.preferResolution,
    required this.preferCodec,
    required this.preferSubtitle,
    required this.preferBitdepth,
    required this.graceHours,
  });

  factory PreferenceProfileRead.fromJson(Map<String, dynamic> json) {
    List<String> readList(String key) {
      final value = json[key];
      return value is List
          ? value.whereType<String>().toList()
          : const <String>[];
    }

    return PreferenceProfileRead(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      isDefault: json['is_default'] as bool? ?? false,
      languageMode: json['language_mode'] as String? ?? '简',
      languageUnknown: json['language_unknown'] as String? ?? 'accept',
      preferResolution: readList('prefer_resolution'),
      preferCodec: readList('prefer_codec'),
      preferSubtitle: readList('prefer_subtitle'),
      preferBitdepth: readList('prefer_bitdepth'),
      graceHours: (json['grace_hours'] as num?)?.toDouble() ?? 3,
    );
  }

  final int id;
  final String name;
  final bool isDefault;
  final String languageMode;
  final String languageUnknown;
  final List<String> preferResolution;
  final List<String> preferCodec;
  final List<String> preferSubtitle;
  final List<String> preferBitdepth;
  final double graceHours;
}

class SubscriptionRead {
  const SubscriptionRead({
    required this.id,
    required this.animeId,
    required this.bangumiId,
    required this.animeName,
    required this.animeNameCn,
    required this.imageUrl,
    required this.enabled,
    required this.profileId,
    required this.fansub,
    required this.allowNoFansub,
    required this.searchKeywords,
    required this.mustInclude,
    required this.excludeKeywords,
    required this.useSubjectId,
    required this.resourceTypes,
    required this.profileOverrides,
    required this.episodeOffsetOverride,
    required this.lastCheckedAt,
    required this.lastFoundAt,
    required this.lastError,
    this.episodeCount = 0,
    this.ownedEpisodeCount = 0,
    this.nextEpisodeIndex,
    this.nextEpisodeAirDate,
    this.needsReviewCount = 0,
  });

  factory SubscriptionRead.fromJson(Map<String, dynamic> json) {
    List<String> readList(String key) {
      final value = json[key];
      return value is List
          ? value.whereType<String>().toList()
          : const <String>[];
    }

    return SubscriptionRead(
      id: json['id'] as int? ?? 0,
      animeId: json['anime_id'] as int? ?? 0,
      bangumiId: json['bangumi_id'] as int? ?? 0,
      animeName: json['anime_name'] as String? ?? '',
      animeNameCn: json['anime_name_cn'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      profileId: json['profile_id'] as int? ?? 0,
      fansub: json['fansub'] as String? ?? '',
      allowNoFansub: json['allow_no_fansub'] as bool? ?? false,
      searchKeywords: readList('search_keywords'),
      mustInclude: readList('must_include'),
      excludeKeywords: readList('exclude_keywords'),
      useSubjectId: json['use_subject_id'] as bool? ?? true,
      resourceTypes: readList('resource_types'),
      profileOverrides: json['profile_overrides'] is Map
          ? Map<String, dynamic>.from(json['profile_overrides'] as Map)
          : null,
      episodeOffsetOverride: json['episode_offset_override'] as int?,
      lastCheckedAt: DateTime.tryParse(
        json['last_checked_at'] as String? ?? '',
      ),
      lastFoundAt: DateTime.tryParse(json['last_found_at'] as String? ?? ''),
      lastError: json['last_error'] as String?,
      episodeCount: json['episode_count'] as int? ?? 0,
      ownedEpisodeCount: json['owned_episode_count'] as int? ?? 0,
      nextEpisodeIndex: json['next_episode_index'] as int?,
      nextEpisodeAirDate: DateTime.tryParse(
        json['next_episode_air_date'] as String? ?? '',
      ),
      needsReviewCount: json['needs_review_count'] as int? ?? 0,
    );
  }

  final int id;
  final int animeId;
  final int bangumiId;
  final String animeName;
  final String animeNameCn;
  final String imageUrl;
  final bool enabled;
  final int profileId;
  /// The one group this show is followed from; empty means unlocked.
  final String fansub;
  final bool allowNoFansub;
  final List<String> searchKeywords;
  final List<String> mustInclude;
  final List<String> excludeKeywords;
  final bool useSubjectId;
  final List<String> resourceTypes;
  final Map<String, dynamic>? profileOverrides;
  final int? episodeOffsetOverride;
  String get displayName => animeNameCn.isEmpty ? animeName : animeNameCn;

  final DateTime? lastCheckedAt;
  final DateTime? lastFoundAt;
  final String? lastError;
  final int episodeCount;
  final int ownedEpisodeCount;
  final int? nextEpisodeIndex;
  final DateTime? nextEpisodeAirDate;
  final int needsReviewCount;
}

class FansubCandidateRead {
  const FansubCandidateRead({
    required this.name,
    required this.count,
    required this.latestAt,
    required this.isNoFansub,
  });

  factory FansubCandidateRead.fromJson(Map<String, dynamic> json) {
    return FansubCandidateRead(
      name: json['name'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      latestAt: DateTime.tryParse(json['latest_at'] as String? ?? ''),
      isNoFansub: json['is_no_fansub'] as bool? ?? false,
    );
  }

  final String name;
  final int count;
  final DateTime? latestAt;
  final bool isNoFansub;
}

class SubscriptionPreviewCandidateRead {
  const SubscriptionPreviewCandidateRead({
    required this.episodeIndex,
    required this.resourceId,
    required this.resourceTitle,
    required this.fansub,
    required this.score,
    required this.state,
    required this.reason,
    required this.selected,
  });

  factory SubscriptionPreviewCandidateRead.fromJson(Map<String, dynamic> json) {
    return SubscriptionPreviewCandidateRead(
      episodeIndex: json['episode_index'] as int?,
      resourceId: json['resource_id'] as int? ?? 0,
      resourceTitle: json['resource_title'] as String? ?? '',
      fansub: json['fansub'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      state: json['state'] as String? ?? '',
      reason: json['reason'] as String?,
      selected: json['selected'] as bool? ?? false,
    );
  }

  final int? episodeIndex;
  final int resourceId;
  final String resourceTitle;
  final String fansub;
  final double score;
  final String state;
  final String? reason;
  final bool selected;
}

class SubscriptionPreviewRead {
  const SubscriptionPreviewRead({
    required this.resourceCount,
    required this.acceptedCount,
    required this.episodeCount,
    required this.airedEpisodeCount,
    required this.ownedEpisodeCount,
    required this.matchedEpisodes,
    required this.missingEpisodes,
    required this.candidates,
  });

  factory SubscriptionPreviewRead.fromJson(Map<String, dynamic> json) {
    final values = json['candidates'];
    List<int> readIndices(String key) {
      final value = json[key];
      return value is List ? value.whereType<int>().toList() : const <int>[];
    }

    return SubscriptionPreviewRead(
      resourceCount: json['resource_count'] as int? ?? 0,
      acceptedCount: json['accepted_count'] as int? ?? 0,
      episodeCount: json['episode_count'] as int? ?? 0,
      airedEpisodeCount: json['aired_episode_count'] as int? ?? 0,
      ownedEpisodeCount: json['owned_episode_count'] as int? ?? 0,
      matchedEpisodes: readIndices('matched_episodes'),
      missingEpisodes: readIndices('missing_episodes'),
      candidates: values is List
          ? values
                .whereType<Map<String, dynamic>>()
                .map(SubscriptionPreviewCandidateRead.fromJson)
                .toList()
          : const [],
    );
  }

  final int resourceCount;
  final int acceptedCount;

  /// The season as the server sees it, independent of the current rules.
  final int episodeCount;
  final int airedEpisodeCount;
  final int ownedEpisodeCount;

  /// Episodes these rules will fetch, and aired ones they cover with nothing.
  final List<int> matchedEpisodes;
  final List<int> missingEpisodes;

  final List<SubscriptionPreviewCandidateRead> candidates;
}
