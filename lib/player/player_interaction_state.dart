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
  double? _speedBeforeSuperSpeed;

  void toggleControls() => showControls.toggle();

  void hideControls() => showControls.value = false;

  void showControlsTemporarily() {
    showControls.value = true;
    _autoHideControls?.cancel();
    _autoHideControls = Timer(const Duration(seconds: 5), hideControls);
  }

  void scheduleSuperSpeed() {
    _superSpeedTimer?.cancel();
    _superSpeedTimer = Timer(const Duration(milliseconds: 150), () {
      if (_controller.disposed) {
        return;
      }
      _superSpeedActive = true;
      _speedBeforeSuperSpeed = _controller.playbackSpeed.value;
      superSpeed.value = true;
      _controller.setSpeed(_controller.options.longPressSpeed);
      HapticFeedback.mediumImpact();
    });
  }

  bool cancelSuperSpeed() {
    _superSpeedTimer?.cancel();
    _superSpeedTimer = null;
    if (!_superSpeedActive) {
      return false;
    }
    _superSpeedActive = false;
    superSpeed.value = false;
    final speed = _speedBeforeSuperSpeed ?? 1;
    _speedBeforeSuperSpeed = null;
    _controller.setSpeed(speed);
    return true;
  }

  void dispose() {
    _autoHideControls?.cancel();
    _superSpeedTimer?.cancel();
    _showControlsSubscription?.cancel();
  }
}
