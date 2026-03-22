import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Progressive App Check bootstrap.
/// Disabled by default so development is not blocked.
class AppCheckService {
  static const bool _enabled =
      bool.fromEnvironment('APP_CHECK_ENABLED', defaultValue: false);
  static const bool _forceDebugProvider =
      bool.fromEnvironment('APP_CHECK_DEBUG_PROVIDER', defaultValue: false);
  static const String _webRecaptchaSiteKey =
      String.fromEnvironment('APP_CHECK_WEB_RECAPTCHA_SITE_KEY');
  static const String _androidDebugToken =
      String.fromEnvironment('APP_CHECK_ANDROID_DEBUG_TOKEN');
  static const String _appleDebugToken =
      String.fromEnvironment('APP_CHECK_APPLE_DEBUG_TOKEN');

  static bool get isEnabled => _enabled;

  static Future<void> initialize() async {
    if (!_enabled) {
      if (kDebugMode) {
        debugPrint('[AppCheck] disabled (APP_CHECK_ENABLED=false)');
      }
      return;
    }

    final appCheck = FirebaseAppCheck.instance;
    final useDebugProvider = kDebugMode || _forceDebugProvider;

    try {
      if (kIsWeb) {
        if (_webRecaptchaSiteKey.isEmpty) {
          if (kDebugMode) {
            debugPrint(
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
        final AndroidAppCheckProvider androidProvider = useDebugProvider
            ? AndroidDebugProvider(
                debugToken:
                    _androidDebugToken.isEmpty ? null : _androidDebugToken,
              )
            : const AndroidPlayIntegrityProvider();
        final AppleAppCheckProvider appleProvider = useDebugProvider
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
        debugPrint('[AppCheck] active, token fetched: ${token != null}');
      }
    } catch (e) {
      // Keep bootstrap non-blocking while rollout is progressive.
      if (kDebugMode) {
        debugPrint('[AppCheck] init failed (non-blocking): $e');
      }
    }
  }
}
