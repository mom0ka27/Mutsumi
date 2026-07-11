extension DurationExtension on Duration {
  String get str {
    // assert(inHours == 0);
    if (inHours == 0) {
      return toString().substring(2, 7);
    } else {
      return toString().substring(0, 7);
    }
  }
}
