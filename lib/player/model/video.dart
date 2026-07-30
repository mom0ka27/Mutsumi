import 'dart:io';
import 'dart:typed_data';

import 'danmaku.dart';

class Video {
  int index;
  String title;
  DanmakuProvider? danmakuProvider;
  String uri;
  String? subtitleUri;
  Uint8List? artwork;

  Video({
    required this.index,
    required this.uri,
    this.subtitleUri,
    required this.title,
    this.danmakuProvider,
    this.artwork,
  });
}

class NetworkVideo extends Video {
  Map<String, String>? httpHeaders;

  NetworkVideo({
    required super.index,
    required super.uri,
    super.subtitleUri,
    required super.title,
    super.danmakuProvider,
    super.artwork,
    this.httpHeaders,
  });
}

class LocalVideo extends Video {
  LocalVideo({
    required super.index,
    required File file,
    required super.title,
    super.danmakuProvider,
    super.artwork,
  }) : super(uri: file.uri.toString());
}
