import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../fs/launcher_dirs.dart';

class Logger {
  static const String _appName = 'Bitig Launcher';
  static IOSink? _fileSink;

  static void debug(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      _log('DEBUG', message, tag: tag, error: error, stackTrace: stackTrace);
    }
  }

  static void info(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log('INFO', message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void warning(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log('WARNING', message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log('ERROR', message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void critical(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log('CRITICAL', message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static Future<void> initFileLogging() async {
    if (_fileSink != null) return;
    try {
      final root = LauncherDirs.dataRoot();
      final dir = Directory('${root.path}/logs');
      await dir.create(recursive: true);
      final latest = File('${dir.path}/latest.log');
      if (await latest.exists()) {
        try {
          await latest.delete();
        } catch (_) {}
      }
      _fileSink = latest.openWrite(mode: FileMode.writeOnlyAppend);
      _fileSink!.writeln('--- session_start ${DateTime.now().toIso8601String()} ---');
    } catch (_) {}
  }

  static void _log(String level, String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final timestamp = DateTime.now().toIso8601String();
    final tagPrefix = tag != null ? '[$tag] ' : '';
    final logMessage = '[$_appName] [$level] $tagPrefix$message';

    developer.log(
      logMessage,
      name: _appName,
      level: _getLogLevel(level),
      error: error,
      stackTrace: stackTrace,
    );

    if (kDebugMode) {
      print('$timestamp $logMessage');
      if (error != null) {
        print('Error: $error');
      }
      if (stackTrace != null) {
        print('Stack trace: $stackTrace');
      }
    }

    final sink = _fileSink;
    if (sink != null) {
      sink.writeln('$timestamp $logMessage');
      if (error != null) sink.writeln('Error: $error');
      if (stackTrace != null) sink.writeln('Stack trace: $stackTrace');
    }
  }

  static int _getLogLevel(String level) {
    switch (level.toUpperCase()) {
      case 'DEBUG':
        return 500;
      case 'INFO':
        return 800;
      case 'WARNING':
        return 900;
      case 'ERROR':
        return 1000;
      case 'CRITICAL':
        return 1200;
      default:
        return 800;
    }
  }
}

class TaggedLogger {
  final String tag;

  const TaggedLogger(this.tag);

  void debug(String message, {Object? error, StackTrace? stackTrace}) {
    Logger.debug(message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void info(String message, {Object? error, StackTrace? stackTrace}) {
    Logger.info(message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    Logger.warning(message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    Logger.error(message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void critical(String message, {Object? error, StackTrace? stackTrace}) {
    Logger.critical(message, tag: tag, error: error, stackTrace: stackTrace);
  }
}
