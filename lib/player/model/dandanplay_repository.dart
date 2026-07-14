import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import 'package:mutsumi/core/logging/app_logger.dart';

import '../../core/storage/local_storage.dart';

class DandanPlayFile {
  const DandanPlayFile({required this.hash, required this.name});

  final String hash;
  final String name;
}

class DandanPlayRepository {
  DandanPlayRepository._();

  static final instance = DandanPlayRepository._();
  static const _baseUrl = 'https://api.dandanplay.net';
  static const _appId = String.fromEnvironment('DANDANPLAY_APP_ID');
  static const _appSecret = String.fromEnvironment('DANDANPLAY_APP_SECRET');
  static const _cacheVersion = 4;

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  bool get isConfigured => _appId.isNotEmpty && _appSecret.isNotEmpty;

  Future<Map<String, int>> matchFiles(
    List<DandanPlayFile> files, {
    String? airDate,
  }) async {
    if (!isConfigured || files.isEmpty) {
      return const {};
    }

    final matched = <String, int>{};
    final pending = <DandanPlayFile>[];
    for (final file in files) {
      final hash = _normalizedHash(file.hash);
      final cached = _readCachedEpisodeId(hash);
      if (cached != null) {
        matched[hash] = cached;
      } else {
        pending.add(file);
      }
    }

    for (var offset = 0; offset < pending.length; offset += 32) {
      final batch = pending.skip(offset).take(32).toList();
      final response = await _request<Map<String, dynamic>>(
        'POST',
        '/api/v2/match/batch',
        data: {
          'requests': batch
              .map(
                (file) => {
                  'fileName': _fileNameWithoutExtension(file.name),
                  'fileHash': file.hash,
                },
              )
              .toList(),
        },
      );
      final results = response['results'];
      if (results is! List) {
        continue;
      }
      final batchHashes = batch.map((file) => file.hash.toLowerCase()).toSet();
      for (final result in results.whereType<Map>()) {
        final hash = result['fileHash']?.toString().toLowerCase();
        final match = result['matchResult'];
        final episodeId = match is Map ? match['episodeId'] : null;
        if (hash == null || !batchHashes.contains(hash)) {
          continue;
        }
        if (episodeId is! num || episodeId <= 0) {
          continue;
        }
        final value = episodeId.toInt();
        await _cacheEpisodeId(hash, value, airDate);
        matched[hash] = value;
      }
    }
    return matched;
  }

  Future<DandanPlayCommentsResult> commentsForFile({
    required String fileHash,
    required String fileName,
    String? airDate,
  }) async {
    if (!isConfigured || fileHash.isEmpty) {
      return const DandanPlayCommentsResult.empty();
    }
    final matches = await matchFiles([
      DandanPlayFile(hash: fileHash, name: fileName),
    ], airDate: airDate);
    final episodeId = matches[_normalizedHash(fileHash)];
    if (episodeId == null) {
      return const DandanPlayCommentsResult.empty();
    }
    final cached = _readCachedComments(episodeId);
    if (cached != null) {
      return DandanPlayCommentsResult(
        episodeId: episodeId,
        comments: cached,
        fromCache: true,
      );
    }
    final response = await _request<Map<String, dynamic>>(
      'GET',
      '/api/v2/comment/$episodeId',
      queryParameters: {'withRelated': true, 'chConvert': 1},
    );
    final comments = response['comments'];
    for (final comment in comments) {
      comment['cid'] = comment['cid']?.toString() ?? '';
    }
    if (comments is! List) {
      return DandanPlayCommentsResult(
        episodeId: episodeId,
        comments: const [],
        fromCache: false,
      );
    }
    final result = comments
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    await _cacheComments(episodeId, result, airDate);
    return DandanPlayCommentsResult(
      episodeId: episodeId,
      comments: result,
      fromCache: false,
    );
  }

  Future<T> _request<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final signature = base64Encode(
      sha256.convert(utf8.encode('$_appId$timestamp$path$_appSecret')).bytes,
    );
    AppLogger.info("${method.toUpperCase()} $path", tag: "DandanPlay");
    final response = await _dio.request<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: Options(
        method: method,
        headers: {
          'X-AppId': _appId,
          'X-Timestamp': timestamp.toString(),
          'X-Signature': signature,
        },
      ),
    );
    final value = response.data;
    if (value == null) {
      throw StateError('弹弹play 返回空数据');
    }
    return value;
  }

  Box get _box => Hive.box(LocalStorage.dandanPlayBoxName);

  String _normalizedHash(String value) => value.trim().toLowerCase();

  int? _readCachedEpisodeId(String hash) {
    final value = _readCache('match_v$_cacheVersion:$hash');
    final episodeId = value?['episodeId'];
    return episodeId is int && episodeId > 0 ? episodeId : null;
  }

  List<Map<String, dynamic>>? _readCachedComments(int episodeId) {
    final value = _readCache('comments_v$_cacheVersion:$episodeId');
    final comments = value?['comments'];
    if (comments is! List) {
      return null;
    }
    return comments
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic>? _readCache(String key) {
    final value = _box.get(key);
    if (value is! Map) {
      return null;
    }
    final cache = Map<String, dynamic>.from(value);
    final expiresAtHours = cache['expiresAtHours'];
    final cachedAtHours = cache['cachedAtHours'];
    final nowHours =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/
        Duration.millisecondsPerHour;
    if (cache['version'] != _cacheVersion ||
        expiresAtHours is! int ||
        cachedAtHours is! int ||
        cachedAtHours > nowHours ||
        expiresAtHours <= nowHours) {
      _box.delete(key);
      return null;
    }
    return cache;
  }

  Future<void> _cacheEpisodeId(String hash, int episodeId, String? airDate) =>
      _writeCache('match_v$_cacheVersion:$hash', {
        'episodeId': episodeId,
      }, airDate);

  Future<void> _cacheComments(
    int episodeId,
    List<Map<String, dynamic>> comments,
    String? airDate,
  ) => _writeCache('comments_v$_cacheVersion:$episodeId', {
    'comments': comments,
  }, airDate);

  Future<void> _writeCache(
    String key,
    Map<String, dynamic> data,
    String? airDate,
  ) {
    final now = DateTime.now().toUtc();
    return _box.put(key, {
      'version': _cacheVersion,
      'cachedAtHours':
          now.millisecondsSinceEpoch ~/ Duration.millisecondsPerHour,
      'expiresAtHours':
          now.add(_cacheTtl(airDate)).millisecondsSinceEpoch ~/
          Duration.millisecondsPerHour,
      ...data,
    });
  }

  Duration _cacheTtl(String? airDate) {
    final year = DateTime.tryParse(airDate ?? '2000-01-01')?.year;
    final currentYear = DateTime.now().toUtc().year;
    final ageYears = year == null || year > currentYear
        ? 0
        : currentYear - year;
    return Duration(hours: (ageYears + 1) * 12);
  }

  DanmakuCacheInfo? getCacheInfo(int episodeId) {
    final value = _readCache('comments_v$_cacheVersion:$episodeId');
    if (value == null) return null;
    final cachedAtHours = value['cachedAtHours'];
    final expiresAtHours = value['expiresAtHours'];
    final commentCount = (value['comments'] as List?)?.length ?? 0;
    if (cachedAtHours is! int || expiresAtHours is! int) return null;
    return DanmakuCacheInfo(
      episodeId: episodeId,
      cachedAt: DateTime.fromMillisecondsSinceEpoch(
        cachedAtHours * Duration.millisecondsPerHour,
        isUtc: true,
      ).toLocal(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAtHours * Duration.millisecondsPerHour,
        isUtc: true,
      ).toLocal(),
      commentCount: commentCount,
    );
  }

  Future<void> clearEpisodeCache(int episodeId) async {
    await _box.delete('comments_v$_cacheVersion:$episodeId');
    for (final key in _box.keys.whereType<String>()) {
      if (!key.startsWith('match_v$_cacheVersion:')) continue;
      final value = _box.get(key);
      if (value is Map && value['episodeId'] == episodeId) {
        await _box.delete(key);
      }
    }
  }

  String _fileNameWithoutExtension(String value) {
    final name = value.split('/').last;
    final extensionIndex = name.lastIndexOf('.');
    return extensionIndex > 0 ? name.substring(0, extensionIndex) : name;
  }
}

class DandanPlayCommentsResult {
  const DandanPlayCommentsResult({
    required this.episodeId,
    required this.comments,
    required this.fromCache,
  });

  const DandanPlayCommentsResult.empty()
    : episodeId = null,
      comments = const [],
      fromCache = false;

  final int? episodeId;
  final List<Map<String, dynamic>> comments;
  final bool fromCache;
}

class DanmakuCacheInfo {
  const DanmakuCacheInfo({
    required this.episodeId,
    required this.cachedAt,
    required this.expiresAt,
    required this.commentCount,
  });

  final int episodeId;
  final DateTime cachedAt;
  final DateTime expiresAt;
  final int commentCount;
}
