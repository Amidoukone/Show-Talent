import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kReleaseMode;

import '../config/app_environment.dart';
import 'client_logger.dart';

enum AppLogLevel { debug, info, warning, error }

class AppLogger {
  AppLogger._();

  static final Random _random = Random();

  static const double productionInfoSampleRate = 0.02;
  static const double productionWarningSampleRate = 0.15;

  static void debug(
    Object? message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      AppLogLevel.debug,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  static void info(
    Object? message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      AppLogLevel.info,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  static void warning(
    Object? message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      AppLogLevel.warning,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  static void error(
    Object? message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      AppLogLevel.error,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  static void _log(
    AppLogLevel level,
    Object? message, {
    required String source,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    final text = message?.toString() ?? '';

    if (kDebugMode) {
      debugPrint(text);
    }

    developer.log(
      text,
      name: source,
      level: _developerLevel(level),
      error: error,
      stackTrace: stackTrace,
    );

    if (!_shouldSendToRemote(level)) {
      return;
    }

    final sanitizedMetadata = _safeMetadata({
      'level': level.name,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
      ...?metadata,
    });

    if (level == AppLogLevel.error || level == AppLogLevel.warning) {
      unawaited(
        ClientLogger.instance.logError(
          source,
          text,
          metadata: sanitizedMetadata,
        ),
      );
      return;
    }

    unawaited(
      ClientLogger.instance.logInfo(
        source,
        text,
        metadata: sanitizedMetadata,
      ),
    );
  }

  static bool _shouldSendToRemote(AppLogLevel level) {
    if (!kReleaseMode || !AppEnvironmentConfig.isProduction) {
      return false;
    }

    switch (level) {
      case AppLogLevel.error:
        return true;
      case AppLogLevel.warning:
        return _random.nextDouble() < productionWarningSampleRate;
      case AppLogLevel.info:
        return _random.nextDouble() < productionInfoSampleRate;
      case AppLogLevel.debug:
        return false;
    }
  }

  static int _developerLevel(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.debug:
        return 500;
      case AppLogLevel.info:
        return 800;
      case AppLogLevel.warning:
        return 900;
      case AppLogLevel.error:
        return 1000;
    }
  }

  static Map<String, dynamic> _safeMetadata(Map<String, dynamic> raw) {
    return raw.map((key, value) {
      if (value == null || value is bool || value is num || value is String) {
        return MapEntry(key, value);
      }
      return MapEntry(key, value.toString());
    })
      ..removeWhere((_, value) => value == null);
  }
}
