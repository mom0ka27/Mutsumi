import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'controller.dart';

class PlayerInteractionState {
  PlayerInteractionState(this._controller) {
    _showControlsSubscription = showControls.listen((visible) {
      _autoHideControls?.cancel();
      if (visible) {
        _autoHideControls = Timer(const Duration(seconds: 5), hideControls);
      }
    });
  }

  final IndexPlayerController _controller;
  final showControls = false.obs;
  final superSpeed = false.obs;
  Timer? _autoHideControls;
  Timer? _superSpeedTimer;
  StreamSubscription<bool>? _showControlsSubscription;
  var _superSpeedActive = false;

  void toggleControls() => showControls.toggle();

  void hideControls() => showControls.value = false;

  void scheduleSuperSpeed() {
    _superSpeedTimer?.cancel();
    _superSpeedTimer = Timer(const Duration(milliseconds: 200), () {
      if (_controller.disposed) {
        return;
      }
      _superSpeedActive = true;
      superSpeed.value = true;
      _controller.setSpeed(2);
      HapticFeedback.mediumImpact();
    });
  }

  void cancelSuperSpeed() {
    _superSpeedTimer?.cancel();
    _superSpeedTimer = null;
    if (!_superSpeedActive) {
      return;
    }
    _superSpeedActive = false;
    superSpeed.value = false;
    _controller.setSpeed(1);
  }

  void dispose() {
    _autoHideControls?.cancel();
    _superSpeedTimer?.cancel();
    _showControlsSubscription?.cancel();
  }
}
