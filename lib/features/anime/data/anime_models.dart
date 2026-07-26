import '../../bangumi/data/bangumi_repository.dart';

/// Data transfer objects for the anime library, split out of
/// `anime_service.dart` so the service file only holds request logic.
/// Re-exported from there, so existing imports keep working.

class WatchProgressRead {
  const WatchProgressRead({required this.episodeId, required this.position});

  factory WatchProgressRead.fromJson(Map<String, dynamic> json) {
    return WatchProgressRead(
      episodeId: json['episode_id'] as int?,
      position: Duration(seconds: json['position_seconds'] as int? ?? 0),
    );
  }

  final int? episodeId;
  final Duration position;
}

class AnimeSubtitle {
  const AnimeSubtitle({required this.filename, required this.name});

  factory AnimeSubtitle.fromJson(Map<String, dynamic> json) {
    final filename = json['filename'] as String? ?? '';
    return AnimeSubtitle(
      filename: filename,
      name: json['name'] as String? ?? filename,
    );
  }

  final String filename;
  final String name;
}

class AnimeEpisodeRead {
  const AnimeEpisodeRead({
    required this.id,
    required this.index,
    required this.name,
    required this.filename,
  });

  factory AnimeEpisodeRead.fromJson(Map<String, dynamic> json) {
    return AnimeEpisodeRead(
      id: json['id'] as int? ?? 0,
      index: json['index'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
    );
  }

  final int id;
  final int index;
  final String name;
  final String filename;

  String get displayName => name.isEmpty ? 'Episode $index' : name;
}

class AnimeRead {
  AnimeRead({
    required this.id,
    required this.bangumiId,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.imageUrl,
    required this.score,
    required this.episodeCount,
    required this.airDate,
    required this.rank,
    required this.platform,
    required this.tags,
    required this.infobox,
    required this.downloadHash,
    required this.episodes,
    required this.watchProgress,
  });

  factory AnimeRead.fromJson(Map<String, dynamic> json) {
    final infobox = json['infobox'];
    final episodes = json['episodes'];
    final progress = json['watch_progress'];
    return AnimeRead(
      id: json['id'] as int? ?? 0,
      bangumiId: json['bangumi_id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['name_cn'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      episodeCount: json['episode_count'] as int? ?? 0,
      airDate: json['air_date'] as String? ?? '',
      rank: json['rank'] as int? ?? 0,
      platform: json['platform'] as String? ?? '',
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      infobox: infobox is List
          ? infobox
                .whereType<Map<String, dynamic>>()
                .map(BangumiInfoItem.fromJson)
                .toList()
          : const [],
      downloadHash: json['download_hash'] as String?,
      episodes: episodes is List
          ? episodes
                .whereType<Map<String, dynamic>>()
                .map(AnimeEpisodeRead.fromJson)
                .toList()
          : const [],
      watchProgress: progress is Map<String, dynamic>
          ? WatchProgressRead.fromJson(progress)
          : null,
    );
  }

  final int id;
  final int bangumiId;
  final String name;
  final String nameCn;
  final String summary;
  final String imageUrl;
  final double score;
  final int episodeCount;
  final String airDate;
  final int rank;
  final String platform;
  final List<String> tags;
  final List<BangumiInfoItem> infobox;
  final String? downloadHash;
  final List<AnimeEpisodeRead> episodes;
  WatchProgressRead? watchProgress;

  String get displayName => nameCn.isEmpty ? name : nameCn;

  String get originalName => nameCn.isEmpty || name == nameCn ? '' : name;

  BangumiSubjectDetail toBangumiSubjectDetail() {
    return BangumiSubjectDetail(
      id: bangumiId,
      name: name,
      nameCn: nameCn,
      summary: summary,
      imageUrl: imageUrl,
      score: score,
      episodeCount: episodeCount,
      airDate: airDate,
      rank: rank,
      platform: platform,
      tags: tags,
      infobox: infobox,
    );
  }
}

class QBittorrentFile {
  const QBittorrentFile({required this.name, required this.size});

  factory QBittorrentFile.fromJson(Map<String, dynamic> json) {
    return QBittorrentFile(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }

  final String name;
  final int size;
}

class AnimeEpisodeCreate {
  const AnimeEpisodeCreate({
    required this.index,
    required this.name,
    required this.filename,
  });

  final int index;
  final String name;
  final String filename;

  Map<String, dynamic> toJson() {
    return {'index': index, 'name': name, 'filename': filename};
  }
}

String? parseBtHash(String magnet) {
  final match = RegExp(
    r'xt=urn:btih:([^&]+)',
    caseSensitive: false,
  ).firstMatch(magnet);
  return match?.group(1);
}

String episodeNameFromFilename(String filename) {
  final segments = filename.split('/');
  final name = segments.isEmpty ? filename : segments.last;
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex <= 0) {
    return name;
  }
  return name.substring(0, dotIndex);
}
