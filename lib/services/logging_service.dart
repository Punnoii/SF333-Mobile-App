import 'dart:developer' as developer;

class LoggingService {
  static const String _defaultCategory = 'PaisabaiApp';

  static void debug(String message, {String category = _defaultCategory}) {
    developer.log(message, name: category, level: 500);
  }

  static void info(String message, {String category = _defaultCategory}) {
    developer.log(message, name: category, level: 800);
  }

  static void warning(String message, {String category = _defaultCategory}) {
    developer.log(message, name: category, level: 900);
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String category = _defaultCategory,
  }) {
    developer.log(
      message,
      name: category,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
