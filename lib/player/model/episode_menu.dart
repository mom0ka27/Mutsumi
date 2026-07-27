import 'package:flutter/foundation.dart';

@immutable
class PlayerEpisodeItem {
  const PlayerEpisodeItem({required this.number, required this.title});

  final int number;
  final String title;
}

@immutable
class PlayerEpisodeMenu {
  const PlayerEpisodeMenu({
    required this.title,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final String title;
  final List<PlayerEpisodeItem> items;
  final int selectedIndex;
  final Future<void> Function(int index) onSelected;
}
