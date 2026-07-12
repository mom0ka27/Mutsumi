import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

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
  static const _matchCacheKey = 'matches_v1';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  bool get isConfigured => _appId.isNotEmpty && _appSecret.isNotEmpty;

  Future<Map<String, int>> matchFiles(List<DandanPlayFile> files) async {
    if (!isConfigured || files.isEmpty) {
      return const {};
    }

    final cache = _matchCache();
    final matched = <String, int>{};
    final pending = <DandanPlayFile>[];
    for (final file in files) {
      final cached = cache[file.hash];
      if (cached is int && cached > 0) {
        matched[file.hash] = cached;
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
        cache[hash] = value;
        matched[hash] = value;
      }
    }
    await _box.put(_matchCacheKey, cache);
    return matched;
  }

  Future<List<Map<String, dynamic>>> commentsForFile({
    required String fileHash,
    required String fileName,
  }) async {
    if (!isConfigured || fileHash.isEmpty) {
      return const [];
    }
    final matches = await matchFiles([
      DandanPlayFile(hash: fileHash, name: fileName),
    ]);
    final episodeId = matches[fileHash.toLowerCase()];
    if (episodeId == null) {
      return const [];
    }
    final cacheKey = 'comments_v1_$episodeId';
    final cached = _box.get(cacheKey);
    if (cached is List) {
      return cached
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    final response = await _request<Map<String, dynamic>>(
      'GET',
      '/api/v2/comment/$episodeId',
      queryParameters: {'withRelated': true, 'chConvert': 1},
    );
    final comments = response['comments'];
    if (comments is! List) {
      return const [];
    }
    final result = comments
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    await _box.put(cacheKey, result);
    return result;
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

  Map<String, dynamic> _matchCache() {
    final value = _box.get(_matchCacheKey);
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  String _fileNameWithoutExtension(String value) {
    final name = value.split('/').last;
    final extensionIndex = name.lastIndexOf('.');
    return extensionIndex > 0 ? name.substring(0, extensionIndex) : name;
  }
}
