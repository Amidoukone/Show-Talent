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

  static Map<String, dynamic> _diagnosticMetadata() => {
    'env': AppEnvironmentConfig.environmentName,
    'enabled': isEnabled,
    'configuredEnabled': _configuredEnabled,
    'androidDebugProvider': _useAndroidDebugProvider,
    'appleDebugProvider': _useAppleDebugProvider,
    'androidDebugTokenConfigured': _androidDebugToken.trim().isNotEmpty,
    'appleDebugTokenConfigured': _appleDebugToken.trim().isNotEmpty,
  };

  static Future<void> initialize() async {
    final bool shouldActivate = isEnabled || _androidDebugProviderRequested;

    if (!shouldActivate) {
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
      if (kIsWeb) {
        if (_webRecaptchaSiteKey.isEmpty) {
          final message =
              '[AppCheck] web site key missing. Set APP_CHECK_WEB_RECAPTCHA_SITE_KEY.';
          if (AppEnvironmentConfig.isProduction) {
            AppLogger.error(
              message,
              source: 'AppCheckService.initialize',
              metadata: _diagnosticMetadata(),
            );
          } else if (kDebugMode) {
            AppLogger.debug(message);
          }
          return;
        }

        await appCheck
            .activate(providerWeb: ReCaptchaV3Provider(_webRecaptchaSiteKey))
            .timeout(const Duration(seconds: 10));
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
            .timeout(const Duration(seconds: 10));
      }

      final token = await appCheck
          .getToken(true)
          .timeout(const Duration(seconds: 8));
      if (token == null || token.isEmpty) {
        AppLogger.error(
          '[AppCheck] active but token is unavailable.',
          source: 'AppCheckService.initialize',
          metadata: _diagnosticMetadata(),
        );
      } else if (kDebugMode) {
        AppLogger.debug('[AppCheck] active, token fetched: true');
      }
    } catch (e, st) {
      // Keep bootstrap non-blocking while rollout is progressive.
      if (AppEnvironmentConfig.isProduction || isEnabled) {
        AppLogger.error(
          '[AppCheck] init failed (non-blocking).',
          source: 'AppCheckService.initialize',
          error: e,
          stackTrace: st,
          metadata: _diagnosticMetadata(),
        );
      } else if (kDebugMode) {
        AppLogger.debug('[AppCheck] init failed (non-blocking): $e');
      }
    }
  }
}
