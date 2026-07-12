import 'package:flutter/widgets.dart';

class AppImageCache {
  const AppImageCache._();

  static int dimension(BuildContext context, double logicalSize) {
    return (logicalSize * MediaQuery.devicePixelRatioOf(context)).round();
  }

  static int backgroundWidth(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return dimension(context, size.width * 0.6);
  }

  static int backgroundHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return dimension(context, size.height * 0.6);
  }
}
