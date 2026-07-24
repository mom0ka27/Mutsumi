import 'dart:developer' as developer;

class AppLogger {
  const AppLogger._();

  static void info(String message, {String tag = 'Mutsumi'}) {
    _write(message, tag: tag, level: 800);
  }

  static void warning(String message, {String tag = 'Mutsumi'}) {
    _write(message, tag: tag, level: 900);
  }

  static void error(
    String message, {
    String tag = 'Mutsumi',
    Object? error,
    StackTrace? stackTrace,
  }) {
    _write(
      message,
      tag: tag,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void _write(
    String message, {
    required String tag,
    required int level,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: tag,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
