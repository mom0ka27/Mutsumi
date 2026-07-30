import 'package:flutter/foundation.dart';

abstract final class AppPlatform {
  static TargetPlatform get current => defaultTargetPlatform;

  static bool get isWeb => kIsWeb;

  static bool get isMobile =>
      !isWeb &&
      (current == TargetPlatform.android || current == TargetPlatform.iOS);

  static bool get isDesktop =>
      !isWeb &&
      (current == TargetPlatform.macOS ||
          current == TargetPlatform.windows ||
          current == TargetPlatform.linux);

  static bool get isIOS => !isWeb && current == TargetPlatform.iOS;
}
