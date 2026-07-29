import 'package:flutter/foundation.dart';

@immutable
class PlayerEpisodeItem {
  const PlayerEpisodeItem({
    required this.id,
    required this.number,
    required this.title,
  });

  final Object id;
  final int number;
  final String title;
}

@immutable
class PlayerEpisodeMenu {
  const PlayerEpisodeMenu({
    required this.title,
    required this.items,
    required this.selectedIndex,
  });

  final String title;
  final List<PlayerEpisodeItem> items;
  final int selectedIndex;
}
