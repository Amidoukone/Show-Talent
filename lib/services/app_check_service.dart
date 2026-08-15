import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;

import '../config/app_environment.dart';

/// Progressive App Check bootstrap.
/// Disabled outside production by default so development is not blocked.
class AppCheckService {
  static const bool _configuredEnabled = bool.fromEnvironment(
    'APP_CHECK_ENABLED',
    defaultValue: false,
  );
  static const bool _forceDebugProvider = bool.fromEnvironment(
    'APP_CHECK_DEBUG_PROVIDER',
    defaultValue: false,
  );
  static const String _androidProviderName = String.fromEnvironment(
    'APP_CHECK_ANDROID_PROVIDER',
  );
  static const String _webRecaptchaSiteKey = String.fromEnvironment(
    'APP_CHECK_WEB_RECAPTCHA_SITE_KEY',
  );
  static const String _androidDebugToken = String.fromEnvironment(
    'APP_CHECK_ANDROID_DEBUG_TOKEN',
  );
  static const String _appleDebugToken = String.fromEnvironment(
    'APP_CHECK_APPLE_DEBUG_TOKEN',
  );
  static const Duration _activationTimeout = Duration(seconds: 15);
  static const Duration _tokenWarmupTimeout = Duration(seconds: 20);

  static Future<void>? _activationFuture;
  static bool _activated = false;

  static bool get _environmentRequiresAppCheck =>
      AppEnvironmentConfig.isProduction;
  static bool get isEnabled =>
      _configuredEnabled || _environmentRequiresAppCheck;
  static bool get _androidDebugProviderRequested =>
      _forceDebugProvider ||
      _androidProviderName.trim().toLowerCase() == 'debug';
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  static bool get _useAndroidDebugProvider =>
      _isAndroid && (_androidDebugProviderRequested || kDebugMode);
  static bool get _useAppleDebugProvider =>
      _isApple && (_forceDebugProvider || kDebugMode);
  static bool get _shouldActivate =>
      isEnabled ||
      _forceDebugProvider ||
      _androidDebugProviderRequested ||
      _useAppleDebugProvider;

  static Map<String, dynamic> _diagnosticMetadata() => {
    'env': AppEnvironmentConfig.environmentName,
    'enabled': isEnabled,
    'activated': _activated,
    'configuredEnabled': _configuredEnabled,
    'androidDebugProvider': _useAndroidDebugProvider,
    'appleDebugProvider': _useAppleDebugProvider,
    'androidDebugTokenConfigured': _androidDebugToken.trim().isNotEmpty,
    'appleDebugTokenConfigured': _appleDebugToken.trim().isNotEmpty,
  };

  static void _logIssue(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    developer.log(
      message,
      name: 'AppCheckService',
      error: error,
      stackTrace: stackTrace,
    );

    if (kDebugMode) {
      AppLogger.debug(
        message,
        source: 'AppCheckService',
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      );
    }
  }

  static Future<void> initialize() async {
    if (!_shouldActivate) {
      if (kDebugMode) {
        AppLogger.debug(
          '[AppCheck] disabled '
          '(APP_CHECK_ENABLED=false, env=${AppEnvironmentConfig.environmentName})',
        );
      }
      return;
    }

    final appCheck = FirebaseAppCheck.instance;

    try {
      _activationFuture ??= _activate(appCheck);
      await _activationFuture;
    } catch (e, st) {
      _activationFuture = null;
      // Keep bootstrap non-blocking while rollout is progressive.
      if (AppEnvironmentConfig.isProduction || isEnabled) {
        _logIssue(
          '[AppCheck] init failed (non-blocking).',
          error: e,
          stackTrace: st,
          metadata: _diagnosticMetadata(),
        );
      } else if (kDebugMode) {
        AppLogger.debug('[AppCheck] init failed (non-blocking): $e');
      }
    }
  }

  static Future<bool> ensureReady({
    bool forceRefresh = false,
    Duration? timeout,
  }) async {
    if (!_shouldActivate) {
      return true;
    }

    final token = await getToken(forceRefresh: forceRefresh, timeout: timeout);
    return token != null && token.isNotEmpty;
  }

  static Future<String?> getToken({
    bool forceRefresh = false,
    Duration? timeout,
  }) async {
    if (!_shouldActivate) {
      return null;
    }

    final appCheck = FirebaseAppCheck.instance;
    try {
      _activationFuture ??= _activate(appCheck);
      await _activationFuture;

      final token = await appCheck
          .getToken(forceRefresh)
          .timeout(timeout ?? _tokenWarmupTimeout);
      final trimmed = token?.trim() ?? '';
      if (trimmed.isEmpty) {
        _logIssue(
          '[AppCheck] active but token is unavailable.',
          metadata: _diagnosticMetadata(),
        );
        return null;
      }
      return trimmed;
    } catch (e, st) {
      if (!_activated) {
        _activationFuture = null;
      }

      if (AppEnvironmentConfig.isProduction || isEnabled) {
        _logIssue(
          '[AppCheck] token unavailable.',
          error: e,
          stackTrace: st,
          metadata: {..._diagnosticMetadata(), 'forceRefresh': forceRefresh},
        );
      } else if (kDebugMode) {
        AppLogger.debug('[AppCheck] token unavailable: $e');
      }
      return null;
    }
  }

  static Future<void> _activate(FirebaseAppCheck appCheck) async {
    if (_activated) {
      return;
    }

    if (kIsWeb) {
      if (_webRecaptchaSiteKey.isEmpty) {
        final message =
            '[AppCheck] web site key missing. Set APP_CHECK_WEB_RECAPTCHA_SITE_KEY.';
        if (AppEnvironmentConfig.isProduction) {
          _logIssue(message, metadata: _diagnosticMetadata());
        } else if (kDebugMode) {
          AppLogger.debug(message);
        }
        return;
      }

      await appCheck
          .activate(providerWeb: ReCaptchaV3Provider(_webRecaptchaSiteKey))
          .timeout(_activationTimeout);
    } else {
      if (_useAndroidDebugProvider || _useAppleDebugProvider) {
        AppLogger.debug('[AppCheck] enabling debug provider for this build.');
      }

      final AndroidAppCheckProvider androidProvider = _useAndroidDebugProvider
          ? AndroidDebugProvider(
              debugToken: _androidDebugToken.isEmpty
                  ? null
                  : _androidDebugToken,
            )
          : const AndroidPlayIntegrityProvider();
      final AppleAppCheckProvider appleProvider = _useAppleDebugProvider
          ? AppleDebugProvider(
              debugToken: _appleDebugToken.isEmpty ? null : _appleDebugToken,
            )
          : const AppleDeviceCheckProvider();

      await appCheck
          .activate(
            providerAndroid: androidProvider,
            providerApple: appleProvider,
          )
          .timeout(_activationTimeout);
    }

    _activated = true;
    unawaited(_warmUpToken(appCheck));
  }

  static Future<void> _warmUpToken(FirebaseAppCheck appCheck) async {
    try {
      final token = await appCheck.getToken(false).timeout(_tokenWarmupTimeout);
      if (token == null || token.isEmpty) {
        _logIssue(
          '[AppCheck] active but token is unavailable.',
          metadata: _diagnosticMetadata(),
        );
      } else if (kDebugMode) {
        AppLogger.debug('[AppCheck] active, token fetched: true');
      }
    } catch (e, st) {
      if (AppEnvironmentConfig.isProduction || isEnabled) {
        _logIssue(
          '[AppCheck] token warm-up failed (non-blocking).',
          error: e,
          stackTrace: st,
          metadata: _diagnosticMetadata(),
        );
      } else if (kDebugMode) {
        AppLogger.debug('[AppCheck] token warm-up failed: $e');
      }
    }
  }
}
