import 'package:dio/dio.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_paths.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../../settings/data/authenticated_server_client.dart';
import '../../settings/data/settings_repository.dart';

class AnimeService {
  AnimeService({SettingsRepository? settingsRepository})
    : _settingsRepository = settingsRepository ?? SettingsRepository();

  final SettingsRepository _settingsRepository;
  late final AuthenticatedServerClient _serverClient =
      AuthenticatedServerClient(settingsRepository: _settingsRepository);

  Future<List<AnimeRead>> listAnimes() async {
    final dio = _serverDio();
    final response = await dio.get<List<dynamic>>(animeApiPath);
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AnimeRead.fromJson)
        .toList();
  }

  Future<AnimeRead> getAnime(int id) async {
    final dio = _serverDio();
    final response = await dio.get<Map<String, dynamic>>('$animeApiPath/$id');
    final data = response.data;
    if (data == null) {
      throw StateError('服务器返回了空 Anime');
    }
    return AnimeRead.fromJson(data);
  }

  Future<void> deleteAnime(int id, {bool deleteFiles = true}) async {
    final dio = _serverDio();
    await dio.delete<void>(
      '$animeApiPath/$id',
      queryParameters: {'delete_files': deleteFiles},
    );
  }

  Future<void> updateWatchProgress({
    required int animeId,
    required int episodeId,
    required Duration position,
  }) async {
    final dio = _serverDio();
    await dio.put<void>(
      '$animeApiPath/$animeId/progress',
      data: {'episode_id': episodeId, 'position_seconds': position.inSeconds},
    );
  }

  String episodeVideoUrl({required int animeId, required int episodeId}) {
    final serverUrl = _settingsRepository.getServerUrl();
    if (serverUrl.isEmpty) {
      throw StateError('请先连接并登录服务器');
    }
    return '$serverUrl$animeApiPath/$animeId/episodes/$episodeId/video';
  }

  Map<String, String> authHeaders() {
    final serverUrl = _settingsRepository.getServerUrl();
    final accessToken = _settingsRepository.getAccessToken(serverUrl);
    if (accessToken == null || accessToken.isEmpty) {
      return const {};
    }
    return {'Authorization': 'Bearer $accessToken'};
  }

  Future<String?> fetchEpisodeFileHash(int animeId, int episodeId) async {
    final dio = _serverDio();
    final response = await dio.get<Map<String, dynamic>>(
      '$animeApiPath/$animeId/episodes/$episodeId/file-hash',
    );
    return response.data?['file_hash'] as String?;
  }

  Future<String> addTorrent(String url) async {
    final dio = _serverDio();
    final response = await dio.post<Map<String, dynamic>>(
      '$qbittorrentApiPath/torrents',
      data: {'url': url},
    );
    return response.data?['hash'] as String? ?? '';
  }

  Future<String> downloadTorrentFiles({
    required String source,
    required List<String> filenames,
  }) async {
    final dio = _serverDio();
    final response = await dio.post<Map<String, dynamic>>(
      '$qbittorrentApiPath/torrents/download',
      data: {'source': source, 'filenames': filenames},
    );
    return response.data?['hash'] as String? ?? '';
  }

  Future<String> createLocalFolder(int bangumiId) async {
    final dio = _serverDio();
    final response = await dio.post<Map<String, dynamic>>(
      '$animeApiPath/local-folder',
      queryParameters: {'bangumi_id': bangumiId},
    );
    return response.data?['folder_id'] as String? ?? '';
  }

  Future<List<QBittorrentFile>> listLocalFiles(String folderId) async {
    final dio = _serverDio();
    final response = await dio.get<List<dynamic>>(
      '$animeApiPath/local-folder/$folderId/files',
    );
    final data = response.data ?? [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(QBittorrentFile.fromJson)
        .toList();
  }

  Future<List<QBittorrentFile>> getTorrentFiles(String source) async {
    final dio = _serverDio();
    final response = await dio.get<List<dynamic>>(
      '$qbittorrentApiPath/torrents/metadata/files',
      queryParameters: {'source': source},
    );
    final data = response.data ?? [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(QBittorrentFile.fromJson)
        .toList();
  }

  Future<List<QBittorrentFile>> pollTorrentFiles(String source) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      final files = await getTorrentFiles(source);
      if (files.isNotEmpty) {
        return files;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return [];
  }

  Future<void> createAnime({
    required BangumiSubject subject,
    String? downloadHash,
    List<AnimeEpisodeCreate>? episodes,
  }) async {
    final dio = _serverDio();

    final hashState = downloadHash == null ? 'null' : 'provided';
    final episodeState = episodes?.length.toString() ?? 'null';
    AppLogger.info(
      '添加 Anime bangumi=${subject.id} hash=$hashState episodes=$episodeState',
      tag: 'Anime',
    );
    await dio.post<void>(
      animeApiPath,
      data: _AnimeCreatePayload(
        subject: subject,
        downloadHash: downloadHash,
        episodes: episodes,
      ).toJson(),
    );
    AppLogger.info('添加 Anime 完成 bangumi=${subject.id}', tag: 'Anime');
  }

  Dio _serverDio() => _serverClient.dio;
}

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

class _AnimeCreatePayload {
  const _AnimeCreatePayload({
    required this.subject,
    required this.downloadHash,
    required this.episodes,
  });

  final BangumiSubject subject;
  final String? downloadHash;
  final List<AnimeEpisodeCreate>? episodes;

  Map<String, dynamic> toJson() {
    return {
      'bangumi_id': subject.id,
      'name': subject.name,
      'name_cn': subject.nameCn,
      'summary': subject.summary,
      'image_url': subject.imageUrl,
      'score': subject.score,
      'episode_count': subject.episodeCount,
      'air_date': subject.airDate,
      'rank': subject is BangumiSubjectDetail
          ? (subject as BangumiSubjectDetail).rank
          : 0,
      'platform': subject is BangumiSubjectDetail
          ? (subject as BangumiSubjectDetail).platform
          : '',
      'tags': subject is BangumiSubjectDetail
          ? (subject as BangumiSubjectDetail).tags
          : <String>[],
      'infobox': subject is BangumiSubjectDetail
          ? (subject as BangumiSubjectDetail).infobox.map((item) {
              return {'key': item.key, 'value': item.value};
            }).toList()
          : <Map<String, String>>[],
      'download_hash': downloadHash,
      'episodes': episodes?.map((episode) => episode.toJson()).toList(),
    };
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
