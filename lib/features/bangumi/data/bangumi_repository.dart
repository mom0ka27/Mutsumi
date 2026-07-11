import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/logging/app_logger.dart';

class BangumiRepository {
  BangumiRepository()
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://api.bgm.tv',
          headers: {
            'accept': 'application/json',
            'content-type': 'application/json',
            'user-agent': "mom0ka27/Mutsumi/1.0.0(${Platform.operatingSystem})",
          },
        ),
      );

  final Dio _dio;

  Future<List<BangumiEpisode>> getEpisodes(int subjectId) async {
    AppLogger.info('获取章节 subject=$subjectId', tag: 'Bangumi');
    final response = await _dio.get<Map<String, dynamic>>(
      '/v0/episodes',
      queryParameters: {'subject_id': subjectId, 'limit': 100, 'offset': 0},
    );
    final data = response.data?['data'];
    if (data is! List) {
      return [];
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(BangumiEpisode.fromJson)
        .toList();
  }

  Future<BangumiSubjectDetail> getSubjectDetail(int id) async {
    AppLogger.info('获取详情 subject=$id', tag: 'Bangumi');
    final response = await _dio.get<Map<String, dynamic>>('/v0/subjects/$id');
    final data = response.data;
    if (data == null) {
      throw StateError('Bangumi 返回了空详情');
    }
    return BangumiSubjectDetail.fromJson(data);
  }

  Future<List<BangumiSubject>> searchAnime(String keyword) async {
    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isEmpty) {
      return [];
    }

    AppLogger.info('搜索动画 keyword=$trimmedKeyword', tag: 'Bangumi');
    final response = await _dio.post<Map<String, dynamic>>(
      '/v0/search/subjects',
      data: {
        'keyword': trimmedKeyword,
        'sort': 'match',
        'filter': {
          'type': [2],
        },
      },
      queryParameters: const {'limit': 20, 'offset': 0},
    );

    final data = response.data?['data'];
    if (data is! List) {
      return [];
    }

    final results = data
        .whereType<Map<String, dynamic>>()
        .map(BangumiSubject.fromJson)
        .toList();
    AppLogger.info('搜索完成 count=${results.length}', tag: 'Bangumi');
    return results;
  }
}

class BangumiEpisode {
  const BangumiEpisode({
    required this.index,
    required this.name,
    required this.nameCn,
  });

  factory BangumiEpisode.fromJson(Map<String, dynamic> json) {
    return BangumiEpisode(
      index: (json['ep'] as num?)?.round() ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['name_cn'] as String? ?? '',
    );
  }

  final int index;
  final String name;
  final String nameCn;

  String get displayName => nameCn.isEmpty ? name : nameCn;
}

class BangumiSubject {
  const BangumiSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.imageUrl,
    required this.score,
    required this.episodeCount,
    required this.airDate,
  });

  factory BangumiSubject.fromJson(Map<String, dynamic> json) {
    final images = json['images'];
    final rating = json['rating'];

    return BangumiSubject(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['name_cn'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      imageUrl: images is Map<String, dynamic>
          ? images['large'] as String? ?? images['common'] as String? ?? ''
          : '',
      score: rating is Map<String, dynamic>
          ? (rating['score'] as num?)?.toDouble() ?? 0
          : 0,
      episodeCount: json['eps'] as int? ?? 0,
      airDate: json['date'] as String? ?? '',
    );
  }

  final int id;
  final String name;
  final String nameCn;
  final String summary;
  final String imageUrl;
  final double score;
  final int episodeCount;
  final String airDate;

  String get displayName => nameCn.isEmpty ? name : nameCn;

  String get originalName => nameCn.isEmpty || name == nameCn ? '' : name;
}

class BangumiSubjectDetail extends BangumiSubject {
  const BangumiSubjectDetail({
    required super.id,
    required super.name,
    required super.nameCn,
    required super.summary,
    required super.imageUrl,
    required super.score,
    required super.episodeCount,
    required super.airDate,
    required this.rank,
    required this.platform,
    required this.tags,
    required this.infobox,
  });

  factory BangumiSubjectDetail.fromJson(Map<String, dynamic> json) {
    final subject = BangumiSubject.fromJson(json);
    final tags = json['tags'];
    final infobox = json['infobox'];

    return BangumiSubjectDetail(
      id: subject.id,
      name: subject.name,
      nameCn: subject.nameCn,
      summary: subject.summary,
      imageUrl: subject.imageUrl,
      score: subject.score,
      episodeCount: subject.episodeCount,
      airDate: subject.airDate,
      rank: json['rank'] as int? ?? 0,
      platform: json['platform'] as String? ?? '',
      tags: tags is List
          ? tags
                .whereType<Map<String, dynamic>>()
                .map((tag) => tag['name'] as String? ?? '')
                .where((name) => name.isNotEmpty)
                .toList()
          : const [],
      infobox: infobox is List
          ? infobox
                .whereType<Map<String, dynamic>>()
                .map(BangumiInfoItem.fromJson)
                .where((item) => item.key.isNotEmpty && item.value.isNotEmpty)
                .toList()
          : const [],
    );
  }

  final int rank;
  final String platform;
  final List<String> tags;
  final List<BangumiInfoItem> infobox;
}

class BangumiInfoItem {
  const BangumiInfoItem({required this.key, required this.value});

  factory BangumiInfoItem.fromJson(Map<String, dynamic> json) {
    return BangumiInfoItem(
      key: json['key'] as String? ?? '',
      value: _stringifyValue(json['value']),
    );
  }

  final String key;
  final String value;

  static String _stringifyValue(Object? value) {
    return switch (value) {
      null => '',
      String text => text,
      List values =>
        values.map(_stringifyValue).where((v) => v.isNotEmpty).join('、'),
      Map map =>
        map.values.map(_stringifyValue).where((v) => v.isNotEmpty).join('、'),
      _ => value.toString(),
    };
  }
}
