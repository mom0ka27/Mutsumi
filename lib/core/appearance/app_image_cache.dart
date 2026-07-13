import 'package:flutter/widgets.dart';

class AppImageCache {
  const AppImageCache._();

  static int dimension(BuildContext context, double logicalSize) {
    return (logicalSize * MediaQuery.devicePixelRatioOf(context)).round();
  }
}
