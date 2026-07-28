import 'package:flutter/services.dart';

import '../platform/app_platform.dart';

abstract final class PlaybackWindow {
  static const _channel = MethodChannel('mutsumi/window');

  static Future<PlaybackWindowLease> enter({
    double aspectRatio = 16 / 9,
  }) async {
    if (!AppPlatform.isDesktop) {
      return PlaybackWindowLease._();
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'beginPlaybackMode',
        {'aspectRatio': aspectRatio},
      );
      final token = result?['token'];
      return PlaybackWindowLease._(token is String ? token : null);
    } on MissingPluginException {
      return PlaybackWindowLease._();
    } on PlatformException {
      return PlaybackWindowLease._();
    }
  }

  static Future<void> _release(String token) async {
    try {
      await _channel.invokeMethod<void>('endPlaybackMode', {'token': token});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

class PlaybackWindowLease {
  PlaybackWindowLease._([this._token]);

  String? _token;

  Future<void> release() async {
    final token = _token;
    _token = null;
    if (token != null) {
      await PlaybackWindow._release(token);
    }
  }
}
