import 'package:dio/dio.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/external_api_dio.dart';

class AnimeGardenRepository {
  AnimeGardenRepository({Dio? dio})
    : _dio = dio ?? createExternalApiDio('https://api.animes.garden');

  final Dio _dio;

  Future<AnimeGardenSearchResult> searchResources(
    String keyword, {
    required int page,
    int pageSize = 30,
  }) async {
    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isEmpty) {
      return const AnimeGardenSearchResult(resources: [], complete: true);
    }

    AppLogger.info(
      '搜索资源 keyword=$trimmedKeyword page=$page',
      tag: 'AnimeGarden',
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/resources',
      queryParameters: {'page': page, 'pageSize': pageSize, 'tracker': true},
      data: {
        'search': [trimmedKeyword],
        'include': ['简'],
        'types': ['动画', '合集'],
      },
    );

    final body = response.data;
    final data = body?['resources'] ?? body?['data'] ?? body?['items'];
    if (data is! List) {
      return const AnimeGardenSearchResult(resources: [], complete: true);
    }

    final resources = data
        .whereType<Map<String, dynamic>>()
        .map(AnimeGardenResource.fromJson)
        .toList();
    final pagination = body?['pagination'];
    final complete =
        body?['complete'] == true ||
        (pagination is Map<String, dynamic> && pagination['complete'] == true);
    AppLogger.info(
      '搜索资源完成 page=$page count=${resources.length} complete=$complete',
      tag: 'AnimeGarden',
    );
    return AnimeGardenSearchResult(resources: resources, complete: complete);
  }
}

class AnimeGardenSearchResult {
  const AnimeGardenSearchResult({
    required this.resources,
    required this.complete,
  });

  final List<AnimeGardenResource> resources;
  final bool complete;
}

class AnimeGardenResourceDetail {
  const AnimeGardenResourceDetail({required this.files});

  factory AnimeGardenResourceDetail.fromJson(Map<String, dynamic> json) {
    final files = json['files'];
    return AnimeGardenResourceDetail(
      files: files is List
          ? files
                .whereType<Map<String, dynamic>>()
                .map(AnimeGardenResourceFile.fromJson)
                .where((file) => file.name.isNotEmpty)
                .toList()
          : const [],
    );
  }

  final List<AnimeGardenResourceFile> files;
}

class AnimeGardenResourceFile {
  const AnimeGardenResourceFile({required this.name, required this.size});

  factory AnimeGardenResourceFile.fromJson(Map<String, dynamic> json) {
    return AnimeGardenResourceFile(
      name: json['name'] as String? ?? '',
      size: json['size'] as String? ?? '',
    );
  }

  final String name;
  final String size;
}

class AnimeGardenResource {
  AnimeGardenResource({
    required this.id,
    required this.provider,
    required this.providerId,
    required this.title,
    required this.type,
    required this.magnet,
    required this.tracker,
    required this.size,
    required this.fansubName,
    required this.publisherName,
    required this.createdAt,
  }) : normalizedTitle = title.toLowerCase();

  factory AnimeGardenResource.fromJson(Map<String, dynamic> json) {
    final fansub = json['fansub'];
    final publisher = json['publisher'];

    return AnimeGardenResource(
      id: json['id'] as int? ?? 0,
      provider: json['provider'] as String? ?? '',
      providerId: json['providerId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? '',
      magnet: json['magnet'] as String? ?? '',
      tracker: json['tracker'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      fansubName: fansub is Map<String, dynamic>
          ? fansub['name'] as String? ?? ''
          : '',
      publisherName: publisher is Map<String, dynamic>
          ? publisher['name'] as String? ?? ''
          : '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  final int id;
  final String provider;
  final String providerId;
  final String title;
  final String type;
  final String magnet;
  final String tracker;
  final int size;
  final String fansubName;
  final String publisherName;
  final DateTime? createdAt;

  final String normalizedTitle;

  String get displaySize {
    if (size <= 0) {
      return '';
    }
    final gb = size / 1024 / 1024;
    if (gb >= 1) {
      return '${gb.toStringAsFixed(1)} GB';
    }
    final mb = size / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get displayGroup {
    if (fansubName.isNotEmpty) {
      return fansubName;
    }
    return publisherName;
  }

  String get downloadLink => tracker.isNotEmpty ? '$magnet$tracker' : magnet;
}
