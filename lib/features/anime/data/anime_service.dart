import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_paths.dart';
import '../../bangumi/data/bangumi_repository.dart';
import '../../settings/data/authenticated_server_client.dart';
import '../../settings/data/settings_repository.dart';
import 'anime_models.dart';

export 'anime_models.dart';

class AnimeService {
  AnimeService({
    SettingsRepository? settingsRepository,
    AuthenticatedServerClient? serverClient,
  }) : _settingsRepository = settingsRepository ?? SettingsRepository(),
       _serverClient = serverClient ?? AuthenticatedServerClient();

  final SettingsRepository _settingsRepository;
  final AuthenticatedServerClient _serverClient;

  Future<List<AnimeRead>> listAnimes() async {
    return _request('获取 Anime 列表', () async {
      final response = await _serverDio().get<List<dynamic>>(animeApiPath);
      return (response.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AnimeRead.fromJson)
          .toList();
    });
  }

  Future<List<SeriesRead>> listSeries() async {
    return _request('获取 Series 列表', () async {
      final response = await _serverDio().get<List<dynamic>>(
        '$animeApiPath/series',
      );
      return (response.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SeriesRead.fromJson)
          .toList();
    });
  }

  Future<SeriesRead> createSeries({
    required String name,
    required List<int> animeIds,
  }) async {
    return _request('新建 Series', () async {
      final response = await _serverDio().post<Map<String, dynamic>>(
        '$animeApiPath/series',
        data: {'name': name, 'anime_ids': animeIds},
      );
      final data = response.data;
      if (data == null) {
        throw StateError('服务器返回了空 Series');
      }
      return SeriesRead.fromJson(data);
    });
  }

  Future<AnimeRead> getAnime(int id) async {
    return _request('获取 Anime 详情 id=$id', () async {
      final response = await _serverDio().get<Map<String, dynamic>>(
        '$animeApiPath/$id',
      );
      final data = response.data;
      if (data == null) {
        throw StateError('服务器返回了空 Anime');
      }
      return AnimeRead.fromJson(data);
    });
  }

  Future<AnimeRead> updateAnimeMetadata({
    required int animeId,
    required BangumiSubject subject,
  }) async {
    return _request('更新 Anime 元数据 bangumi=${subject.id}', () async {
      final response = await _serverDio().put<Map<String, dynamic>>(
        '$animeApiPath/$animeId/metadata',
        data: _AnimeMetadataPayload(subject).toJson(),
      );
      final data = response.data;
      if (data == null) {
        throw StateError('服务器返回了空 Anime');
      }
      return AnimeRead.fromJson(data);
    });
  }

  Future<void> deleteAnime(int id, {bool deleteFiles = true}) async {
    await _request('删除 Anime id=$id', () {
      return _serverDio().delete<void>(
        '$animeApiPath/$id',
        queryParameters: {'delete_files': deleteFiles},
      );
    });
  }

  Future<void> updateWatchProgress({
    required int animeId,
    required int episodeId,
    required Duration position,
  }) async {
    await _request('同步播放进度 anime=$animeId episode=$episodeId', () {
      return _serverDio().put<void>(
        '$animeApiPath/$animeId/progress',
        data: {'episode_id': episodeId, 'position_seconds': position.inSeconds},
      );
    });
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
    try {
      final response = await _serverDio().get<Map<String, dynamic>>(
        '$animeApiPath/$animeId/episodes/$episodeId/file-hash',
      );
      return response.data?['file_hash'] as String?;
    } catch (error, stackTrace) {
      AppLogger.error(
        '获取 Episode 文件哈希失败 anime=$animeId episode=$episodeId',
        tag: 'Anime',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<AnimeSubtitle>> listEpisodeSubtitles(
    int animeId,
    int episodeId,
  ) async {
    return _request(
      '搜索 Episode 字幕 anime=$animeId episode=$episodeId',
      () async {
        final response = await _serverDio().get<List<dynamic>>(
          '$animeApiPath/$animeId/episodes/$episodeId/subtitles',
        );
        return response.data
                ?.whereType<Map<String, dynamic>>()
                .map(AnimeSubtitle.fromJson)
                .toList() ??
            const [];
      },
    );
  }

  Future<String?> downloadEpisodeSubtitle({
    required int animeId,
    required int episodeId,
    required String filename,
  }) async {
    return _request(
      '下载 Episode 字幕 anime=$animeId episode=$episodeId',
      () async {
        final fileResponse = await _serverDio().get<List<int>>(
          '$animeApiPath/$animeId/episodes/$episodeId/subtitles/file',
          queryParameters: {'filename': filename},
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = fileResponse.data;
        if (bytes == null || bytes.isEmpty) {
          return null;
        }

        final directory = Directory(
          '${(await getTemporaryDirectory()).path}/mutsumi_subtitles',
        );
        await directory.create(recursive: true);
        final suffix = filename.contains('.')
            ? filename.substring(filename.lastIndexOf('.'))
            : '';
        final hash = sha1.convert(utf8.encode(filename)).toString();
        final file = File('${directory.path}/$animeId-$episodeId-$hash$suffix');
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      },
    );
  }

  Future<String> addTorrent(String url) async {
    return _request('添加种子', () async {
      final response = await _serverDio().post<Map<String, dynamic>>(
        '$qbittorrentApiPath/torrents',
        data: {'url': url},
      );
      return response.data?['hash'] as String? ?? '';
    });
  }

  Future<String> downloadTorrentFiles({
    required String source,
    required List<String> filenames,
  }) async {
    return _request('开始下载种子文件', () async {
      final response = await _serverDio().post<Map<String, dynamic>>(
        '$qbittorrentApiPath/torrents/download',
        data: {'source': source, 'filenames': filenames},
      );
      return response.data?['hash'] as String? ?? '';
    });
  }

  Future<String> createLocalFolder(int bangumiId) async {
    return _request('创建本地文件夹 bangumi=$bangumiId', () async {
      final response = await _serverDio().post<Map<String, dynamic>>(
        '$animeApiPath/local-folder',
        queryParameters: {'bangumi_id': bangumiId},
      );
      return response.data?['folder_id'] as String? ?? '';
    });
  }

  Future<List<QBittorrentFile>> listLocalFiles(String folderId) async {
    return _request('获取本地文件夹内容', () async {
      final response = await _serverDio().get<List<dynamic>>(
        '$animeApiPath/local-folder/$folderId/files',
      );
      final data = response.data ?? [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(QBittorrentFile.fromJson)
          .toList();
    });
  }

  Future<List<QBittorrentFile>> getTorrentFiles(String source) async {
    return _request('获取种子文件列表', () async {
      final response = await _serverDio().get<List<dynamic>>(
        '$qbittorrentApiPath/torrents/metadata/files',
        queryParameters: {'source': source},
      );
      final data = response.data ?? [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(QBittorrentFile.fromJson)
          .toList();
    });
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
    final hashState = downloadHash == null ? 'null' : 'provided';
    final episodeState = episodes?.length.toString() ?? 'null';
    AppLogger.info(
      '添加 Anime bangumi=${subject.id} hash=$hashState episodes=$episodeState',
      tag: 'Anime',
    );
    await _request('添加 Anime bangumi=${subject.id}', () {
      return _serverDio().post<void>(
        animeApiPath,
        data: _AnimeCreatePayload(
          subject: subject,
          downloadHash: downloadHash,
          episodes: episodes,
        ).toJson(),
      );
    });
    AppLogger.info('添加 Anime 完成 bangumi=${subject.id}', tag: 'Anime');
  }

  Dio _serverDio() => _serverClient.dio;

  Future<T> _request<T>(String operation, Future<T> Function() request) async {
    try {
      return await request();
    } catch (error, stackTrace) {
      AppLogger.error(
        '$operation 失败',
        tag: 'Anime',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
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
      'media_type': subject is BangumiSubjectDetail
          ? _mediaTypeOf((subject as BangumiSubjectDetail).platform)
          : 'unknown',
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

class _AnimeMetadataPayload {
  const _AnimeMetadataPayload(this.subject);

  final BangumiSubject subject;

  Map<String, dynamic> toJson() {
    return {
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
      'media_type': subject is BangumiSubjectDetail
          ? _mediaTypeOf((subject as BangumiSubjectDetail).platform)
          : 'unknown',
      'tags': subject is BangumiSubjectDetail
          ? (subject as BangumiSubjectDetail).tags
          : <String>[],
      'infobox': subject is BangumiSubjectDetail
          ? (subject as BangumiSubjectDetail).infobox
                .map((item) => {'key': item.key, 'value': item.value})
                .toList()
          : <Map<String, String>>[],
    };
  }
}

String _mediaTypeOf(String platform) {
  final value = platform.trim().toLowerCase();
  if (value.contains('tv')) return 'tv';
  if (value.contains('剧场') || value.contains('movie')) return 'movie';
  if (value.contains('ova')) return 'ova';
  if (value.contains('ona') || value.contains('web')) return 'ona';
  if (value.contains('special') || value.contains('sp')) return 'special';
  return value.isEmpty ? 'unknown' : value;
}
