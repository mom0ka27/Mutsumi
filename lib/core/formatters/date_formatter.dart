extension DateTimeFormat on DateTime {
  String get yyyyMMddHHmm =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} '
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
