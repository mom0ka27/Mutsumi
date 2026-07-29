import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutsumi/player/player_keyboard.dart';

void main() {
  test('播放器键盘快捷键映射正确', () {
    expect(
      playerKeyboardActionFor(LogicalKeyboardKey.space),
      PlayerKeyboardAction.togglePlayback,
    );
    expect(
      playerKeyboardActionFor(LogicalKeyboardKey.arrowLeft),
      PlayerKeyboardAction.seekBackward,
    );
    expect(
      playerKeyboardActionFor(LogicalKeyboardKey.arrowRight),
      PlayerKeyboardAction.seekForward,
    );
    expect(
      playerKeyboardActionFor(LogicalKeyboardKey.arrowUp),
      PlayerKeyboardAction.volumeUp,
    );
    expect(
      playerKeyboardActionFor(LogicalKeyboardKey.arrowDown),
      PlayerKeyboardAction.volumeDown,
    );
  });

  test('未配置的按键不触发播放器动作', () {
    expect(playerKeyboardActionFor(LogicalKeyboardKey.keyA), isNull);
  });
}
