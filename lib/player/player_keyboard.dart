import 'package:flutter/services.dart';

enum PlayerKeyboardAction {
  togglePlayback,
  seekBackward,
  seekForward,
  volumeUp,
  volumeDown,
}

PlayerKeyboardAction? playerKeyboardActionFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) {
    return PlayerKeyboardAction.togglePlayback;
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    return PlayerKeyboardAction.seekBackward;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    return PlayerKeyboardAction.seekForward;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    return PlayerKeyboardAction.volumeUp;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    return PlayerKeyboardAction.volumeDown;
  }
  return null;
}
