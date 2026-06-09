import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;

/// Progressive App Check bootstrap.
/// Disabled by default so development is not blocked.
class AppCheckService {
  static const bool _enabled =
      bool.fromEnvironment('APP_CHECK_ENABLED', defaultValue: false);
  static const bool _forceDebugProvider =
      bool.fromEnvironment('APP_CHECK_DEBUG_PROVIDER', defaultValue: false);
  static const String _androidProviderName =
      String.fromEnvironment('APP_CHECK_ANDROID_PROVIDER');
  static const String _webRecaptchaSiteKey =
      String.fromEnvironment('APP_CHECK_WEB_RECAPTCHA_SITE_KEY');
  static const String _androidDebugToken =
      String.fromEnvironment('APP_CHECK_ANDROID_DEBUG_TOKEN');
  static const String _appleDebugToken =
      String.fromEnvironment('APP_CHECK_APPLE_DEBUG_TOKEN');

  static bool get isEnabled => _enabled;
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

  static Future<void> initialize() async {
    final bool shouldActivate = _enabled || _androidDebugProviderRequested;

    if (!shouldActivate) {
      if (kDebugMode) {
        AppLogger.debug('[AppCheck] disabled (APP_CHECK_ENABLED=false)');
      }
      return;
    }

    final appCheck = FirebaseAppCheck.instance;

    try {
      if (kIsWeb) {
        if (_webRecaptchaSiteKey.isEmpty) {
          if (kDebugMode) {
            AppLogger.debug(
              '[AppCheck] web site key missing. '
              'Set APP_CHECK_WEB_RECAPTCHA_SITE_KEY.',
            );
          }
          return;
        }

        await appCheck.activate(
          providerWeb: ReCaptchaV3Provider(_webRecaptchaSiteKey),
        );
      } else {
        if (_useAndroidDebugProvider || _useAppleDebugProvider) {
          AppLogger.debug(
            '[AppCheck] enabling debug provider for this build.',
          );
        }

        final AndroidAppCheckProvider androidProvider = _useAndroidDebugProvider
            ? AndroidDebugProvider(
                debugToken:
                    _androidDebugToken.isEmpty ? null : _androidDebugToken,
              )
            : const AndroidPlayIntegrityProvider();
        final AppleAppCheckProvider appleProvider = _useAppleDebugProvider
            ? AppleDebugProvider(
                debugToken: _appleDebugToken.isEmpty ? null : _appleDebugToken,
              )
            : const AppleDeviceCheckProvider();

        await appCheck.activate(
          providerAndroid: androidProvider,
          providerApple: appleProvider,
        );
      }

      if (kDebugMode) {
        final token = await appCheck.getToken(true);
        AppLogger.debug('[AppCheck] active, token fetched: ${token != null}');
      }
    } catch (e) {
      // Keep bootstrap non-blocking while rollout is progressive.
      if (kDebugMode) {
        AppLogger.debug('[AppCheck] init failed (non-blocking): $e');
      }
    }
  }
}
