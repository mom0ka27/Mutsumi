import 'package:flutter/material.dart';

extension BuildContextScreenExtension on BuildContext {
  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;
}
