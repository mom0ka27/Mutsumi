import 'package:flutter/foundation.dart';

import 'video.dart';

@immutable
class PlayerPlaylist {
  const PlayerPlaylist({required this.title, required this.items});

  final String title;
  final List<PlayerPlaylistItem> items;
}

@immutable
class PlayerPlaylistItem {
  const PlayerPlaylistItem({
    required this.id,
    required this.number,
    required this.title,
    required this.load,
    this.initialPosition,
  });

  final Object id;
  final int number;
  final String title;
  final Future<PlayerMedia> Function() load;
  final Duration? initialPosition;
}

@immutable
class PlayerMedia {
  const PlayerMedia({
    required this.video,
    this.externalSubtitlePaths = const [],
  });

  final Video video;
  final List<String> externalSubtitlePaths;
}

@immutable
class PlayerPlaybackSnapshot {
  const PlayerPlaybackSnapshot({
    required this.itemId,
    required this.index,
    required this.position,
  });

  final Object itemId;
  final int index;
  final Duration position;
}
