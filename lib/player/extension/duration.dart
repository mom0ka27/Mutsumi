extension DurationExtension on Duration {
  String get str {
    final totalSeconds = inSeconds.clamp(0, 8640000);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final minuteText = minutes.toString().padLeft(2, '0');
    final secondText = seconds.toString().padLeft(2, '0');
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minuteText:$secondText'
        : '$minuteText:$secondText';
  }
}
