import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        visibleForTesting;

import '../config/app_environment.dart';

/// Progressive App Check bootstrap.
///
/// Two invariants hold everywhere in this class, and callers must preserve
/// them:
///
/// 1. **Nothing here ever blocks a user action.** App Check attestation
///    (Play Integrity on Android) fails outright on a meaningful share of the
///    real device fleet — Play-uncertified handsets, missing or outdated
///    Google Play services, or simply a first attestation slower than any
///    timeout worth imposing. Production logs for this project showed both
///    `403 App attestation failed` and repeated activation timeouts.
/// 2. **A missing token is a normal outcome, not an error state.** It is
///    reported for measurement and retried in the background, never surfaced
///    to the user and never used to refuse an operation.
///
/// What actually secures the backend is the Firebase ID token, the Firestore
/// and Storage rules, and the server-side ownership/quota checks in the
/// callables. App Check is an additional anti-abuse signal layered on top.
/// Treating it as a gate turned one flaky Google service into a total outage
/// of the app's core feature.
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
  // Deliberately short. Nothing in the app waits on App Check any more, so a
  // long timeout buys nothing: it only keeps a doomed Play Integrity
  // handshake alive. A failed attempt is retried in the background instead
  // (see _scheduleActivationRetry), which is what actually recovers the
  // common "Play services woke up late" case.
  static const Duration _activationTimeout = Duration(seconds: 8);
  static const Duration _tokenWarmupTimeout = Duration(seconds: 8);
  // Callers asking for a token are always on a user-visible path, so cap how
  // long they can be made to wait before continuing without one.
  static const Duration _defaultTokenTimeout = Duration(seconds: 5);
  static const List<Duration> _activationRetryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 20),
    Duration(seconds: 60),
  ];

  static const Duration _activationCooldown = Duration(minutes: 10);

  static Future<void>? _activationFuture;
  static bool _activated = false;
  static int _activationAttempts = 0;
  static Timer? _activationRetryTimer;
  static DateTime? _activationCooldownUntil;

  /// True once an App Check token has been obtained at least once in this
  /// process. Purely informational — no code path may gate a user action on
  /// it (see the class doc): it exists so diagnostics can report whether
  /// attestation is healthy on this device.
  static bool get hasEverProducedToken => _hasEverProducedToken;
  static bool _hasEverProducedToken = false;

  @visibleForTesting
  static void resetForTest() {
    _activationRetryTimer?.cancel();
    _activationRetryTimer = null;
    _activationFuture = null;
    _activated = false;
    _activationAttempts = 0;
    _activationCooldownUntil = null;
    _hasEverProducedToken = false;
  }

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

  /// Starts App Check activation. Returns as soon as the attempt settles and
  /// never throws — callers are expected to fire this and move on.
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

    await _ensureActivated();
  }

  /// Kept for source compatibility with older call sites.
  ///
  /// Always resolves to `true`: no caller may refuse an operation because
  /// App Check produced nothing (see the class doc). It still triggers
  /// activation/token acquisition in the background so a token is more likely
  /// to be attached to the requests that follow.
  static Future<bool> ensureReady({
    bool forceRefresh = false,
    Duration? timeout,
  }) async {
    if (!_shouldActivate) {
      return true;
    }

    unawaited(getToken(forceRefresh: forceRefresh, timeout: timeout));
    return true;
  }

  /// Best-effort App Check token.
  ///
  /// Returns `null` — quickly and without throwing — whenever attestation is
  /// unavailable, still warming up, or slower than [timeout]. A `null` here
  /// means "send the request without the header", never "abort the request".
  static Future<String?> getToken({
    bool forceRefresh = false,
    Duration? timeout,
  }) async {
    if (!_shouldActivate) {
      return null;
    }

    final budget = timeout ?? _defaultTokenTimeout;
    final deadline = DateTime.now().add(budget);

    if (!_activated) {
      // Bounded: if activation hasn't landed within the caller's budget we
      // continue without a token rather than holding up the user action.
      await _ensureActivated().timeout(budget, onTimeout: () {});
      if (!_activated) {
        return null;
      }
    }

    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return null;
    }

    try {
      final token = await FirebaseAppCheck.instance
          .getToken(forceRefresh)
          .timeout(remaining);
      final trimmed = token?.trim() ?? '';
      if (trimmed.isEmpty) {
        return null;
      }
      _hasEverProducedToken = true;
      return trimmed;
    } catch (e, st) {
      // Logged at debug level only. This is an expected outcome on devices
      // where Play Integrity can't attest, and logging it as an error on
      // every call buried the failures that actually matter.
      if (kDebugMode) {
        AppLogger.debug('[AppCheck] token unavailable: $e');
      } else {
        developer.log(
          '[AppCheck] token unavailable.',
          name: 'AppCheckService',
          error: e,
          stackTrace: st,
        );
      }
      return null;
    }
  }

  static Future<void> _ensureActivated() async {
    if (_activated) {
      return;
    }

    // Circuit breaker. On a device that simply cannot attest (no Play
    // services, uncertified hardware), every attempt is a guaranteed
    // multi-second failure. Without this, each callable would pay that cost
    // again — trading the old hard failure for a permanent latency tax.
    final cooldownUntil = _activationCooldownUntil;
    if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
      return;
    }

    final appCheck = FirebaseAppCheck.instance;
    final pending = _activationFuture ??= _activate(appCheck);

    try {
      await pending;
    } catch (e, st) {
      _activationFuture = null;
      _scheduleActivationRetry();

      // Only the first failure is reported remotely. Repeated identical
      // failures on the same device add no information and previously
      // flooded client_logs on every cold start.
      if (_activationAttempts <= 1 &&
          (AppEnvironmentConfig.isProduction || isEnabled)) {
        _logIssue(
          '[AppCheck] activation failed (non-blocking, will retry).',
          error: e,
          stackTrace: st,
          metadata: _diagnosticMetadata(),
        );
      } else if (kDebugMode) {
        AppLogger.debug('[AppCheck] activation failed (non-blocking): $e');
      }
    }
  }

  // A first attestation can fail simply because Google Play services hasn't
  // finished waking up, or because the device just came back online. Retrying
  // on a widening delay recovers those cases without ever making the user
  // wait, where the previous one-shot activation left the process with no
  // token for its whole lifetime.
  static void _scheduleActivationRetry() {
    if (_activated || _activationRetryTimer != null) {
      return;
    }

    final index = _activationAttempts - 1;
    if (index < 0 || index >= _activationRetryDelays.length) {
      // Retries exhausted: back off for a while before letting any caller
      // trigger another attestation attempt.
      _activationCooldownUntil = DateTime.now().add(_activationCooldown);
      return;
    }

    _activationRetryTimer = Timer(_activationRetryDelays[index], () {
      _activationRetryTimer = null;
      if (_activated) {
        return;
      }
      unawaited(_ensureActivated());
    });
  }

  static Future<void> _activate(FirebaseAppCheck appCheck) async {
    if (_activated) {
      return;
    }

    _activationAttempts++;

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
        if (kDebugMode) {
          AppLogger.debug('[AppCheck] active but token is unavailable.');
        }
        return;
      }
      _hasEverProducedToken = true;
      if (kDebugMode) {
        AppLogger.debug('[AppCheck] active, token fetched: true');
      }
    } catch (e, st) {
      // Warm-up only. Failing here costs nothing: every later getToken() call
      // retries, and no user-facing path depends on the result.
      developer.log(
        '[AppCheck] token warm-up failed (non-blocking).',
        name: 'AppCheckService',
        error: e,
        stackTrace: st,
      );
    }
  }
}
