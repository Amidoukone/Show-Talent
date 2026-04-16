import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../firebase_options.dart';

enum AppEnvironment { local, staging, production }

AppEnvironment _parseAppEnvironment(String rawValue) {
  switch (rawValue.trim().toLowerCase()) {
    case 'local':
      return AppEnvironment.local;
    case 'staging':
      return AppEnvironment.staging;
    default:
      return AppEnvironment.production;
  }
}

class AppEnvironmentConfig {
  AppEnvironmentConfig._();

  static const String _rawAppEnvironment =
      String.fromEnvironment('APP_ENV', defaultValue: 'production');
  static const bool useFirebaseEmulators =
      bool.fromEnvironment('USE_FIREBASE_EMULATORS', defaultValue: false);
  static const String functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'europe-west1',
  );
  static const String _firebaseEmulatorHost =
      String.fromEnvironment('FIREBASE_EMULATOR_HOST');
  static const int authEmulatorPort = int.fromEnvironment(
    'FIREBASE_AUTH_EMULATOR_PORT',
    defaultValue: 9099,
  );
  static const int firestoreEmulatorPort = int.fromEnvironment(
    'FIREBASE_FIRESTORE_EMULATOR_PORT',
    defaultValue: 8080,
  );
  static const int functionsEmulatorPort = int.fromEnvironment(
    'FIREBASE_FUNCTIONS_EMULATOR_PORT',
    defaultValue: 5001,
  );
  static const int storageEmulatorPort = int.fromEnvironment(
    'FIREBASE_STORAGE_EMULATOR_PORT',
    defaultValue: 9199,
  );
  static const String _customEmailActionHost = String.fromEnvironment(
    'EMAIL_LINK_CUSTOM_HOST',
    defaultValue: '',
  );
  static const String _extraEmailAllowedHosts =
      String.fromEnvironment('EMAIL_LINK_ALLOWED_HOSTS');
  static const String _firebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String _firebaseStorageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const String _webApiKey =
      String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const String _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const String _webAuthDomain =
      String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN');
  static const String _androidApiKey =
      String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const String _androidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const String _iosApiKey =
      String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const String _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String _iosBundleId =
      String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  static const String _macosApiKey =
      String.fromEnvironment('FIREBASE_MACOS_API_KEY');
  static const String _macosAppId =
      String.fromEnvironment('FIREBASE_MACOS_APP_ID');
  static const String _macosBundleId =
      String.fromEnvironment('FIREBASE_MACOS_BUNDLE_ID');
  static const String _windowsApiKey =
      String.fromEnvironment('FIREBASE_WINDOWS_API_KEY');
  static const String _windowsAppId =
      String.fromEnvironment('FIREBASE_WINDOWS_APP_ID');
  static const String _windowsAuthDomain =
      String.fromEnvironment('FIREBASE_WINDOWS_AUTH_DOMAIN');

  static AppEnvironment get environment =>
      _parseAppEnvironment(_rawAppEnvironment);

  static String get environmentName => environment.name;

  static bool get isLocal => environment == AppEnvironment.local;

  static bool get isStaging => environment == AppEnvironment.staging;

  static bool get isProduction => environment == AppEnvironment.production;

  static String get firebaseEmulatorHost {
    if (_firebaseEmulatorHost.isNotEmpty) {
      return _firebaseEmulatorHost;
    }
    if (kIsWeb) {
      return '127.0.0.1';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
  }

  static FirebaseOptions get firebaseOptions {
    if (kIsWeb) {
      return _webOptions;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidOptions;
      case TargetPlatform.iOS:
        return _iosOptions;
      case TargetPlatform.macOS:
        return _macosOptions;
      case TargetPlatform.windows:
        return _windowsOptions;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'FirebaseOptions are not configured for linux in this project.',
        );
      default:
        throw UnsupportedError(
          'FirebaseOptions are not supported for this platform.',
        );
    }
  }

  static String get firebaseProjectId => firebaseOptions.projectId;

  static String get emailLinkHost {
    final customHost = _customEmailActionHost.trim().toLowerCase();
    if (customHost.isNotEmpty) {
      return customHost;
    }

    final authDomain = _webAuthDomain.trim().toLowerCase();
    if (authDomain.isNotEmpty) {
      return authDomain;
    }

    return '$firebaseProjectId.firebaseapp.com';
  }

  static Uri buildEmailActionUri({String path = '/verify'}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri(
      scheme: 'https',
      host: emailLinkHost,
      path: normalizedPath,
    );
  }

  static String get emailVerificationActionUrl =>
      buildEmailActionUri(path: '/verify').toString();

  static String get passwordResetActionUrl =>
      buildEmailActionUri(path: '/reset').toString();

  static ActionCodeSettings buildEmailVerificationActionCodeSettings() {
    return ActionCodeSettings(
      url: emailVerificationActionUrl,
      handleCodeInApp: true,
      androidPackageName: androidPackageName,
      androidInstallApp: true,
      iOSBundleId: iosBundleId,
    );
  }

  static ActionCodeSettings buildPasswordResetActionCodeSettings() {
    return ActionCodeSettings(
      url: passwordResetActionUrl,
      handleCodeInApp: true,
      androidPackageName: androidPackageName,
      androidInstallApp: true,
      iOSBundleId: iosBundleId,
    );
  }

  static String get androidPackageName {
    switch (environment) {
      case AppEnvironment.local:
        return 'org.adfoot.app.local';
      case AppEnvironment.staging:
        return 'org.adfoot.app.staging';
      case AppEnvironment.production:
        return 'org.adfoot.app';
    }
  }

  static String get iosBundleId {
    switch (environment) {
      case AppEnvironment.local:
        return 'org.adfoot.app.local';
      case AppEnvironment.staging:
        return 'org.adfoot.app.staging';
      case AppEnvironment.production:
        return 'org.adfoot.app';
    }
  }

  static Set<String> get emailLinkAllowedHosts {
    final hosts = <String>{
      emailLinkHost,
      '$firebaseProjectId.web.app',
      '$firebaseProjectId.firebaseapp.com',
    };

    for (final host in _parseCsv(_extraEmailAllowedHosts)) {
      hosts.add(host.toLowerCase());
    }

    return hosts;
  }

  static FirebaseOptions get _webOptions {
    final defaults = DefaultFirebaseOptions.web;
    return FirebaseOptions(
      apiKey: _valueOrFallback(_webApiKey, defaults.apiKey),
      appId: _valueOrFallback(_webAppId, defaults.appId),
      messagingSenderId: _valueOrFallback(
        _firebaseMessagingSenderId,
        defaults.messagingSenderId,
      ),
      projectId: _valueOrFallback(_firebaseProjectId, defaults.projectId),
      authDomain: _valueOrFallback(_webAuthDomain, defaults.authDomain),
      storageBucket: _valueOrFallback(
        _firebaseStorageBucket,
        defaults.storageBucket,
      ),
    );
  }

  static FirebaseOptions get _androidOptions {
    final defaults = DefaultFirebaseOptions.android;
    return FirebaseOptions(
      apiKey: _valueOrFallback(_androidApiKey, defaults.apiKey),
      appId: _valueOrFallback(_androidAppId, defaults.appId),
      messagingSenderId: _valueOrFallback(
        _firebaseMessagingSenderId,
        defaults.messagingSenderId,
      ),
      projectId: _valueOrFallback(_firebaseProjectId, defaults.projectId),
      storageBucket: _valueOrFallback(
        _firebaseStorageBucket,
        defaults.storageBucket,
      ),
    );
  }

  static FirebaseOptions get _iosOptions {
    final defaults = DefaultFirebaseOptions.ios;
    return FirebaseOptions(
      apiKey: _valueOrFallback(_iosApiKey, defaults.apiKey),
      appId: _valueOrFallback(_iosAppId, defaults.appId),
      messagingSenderId: _valueOrFallback(
        _firebaseMessagingSenderId,
        defaults.messagingSenderId,
      ),
      projectId: _valueOrFallback(_firebaseProjectId, defaults.projectId),
      storageBucket: _valueOrFallback(
        _firebaseStorageBucket,
        defaults.storageBucket,
      ),
      iosBundleId: _valueOrFallback(_iosBundleId, defaults.iosBundleId),
    );
  }

  static FirebaseOptions get _macosOptions {
    final defaults = DefaultFirebaseOptions.macos;
    return FirebaseOptions(
      apiKey: _valueOrFallback(_macosApiKey, defaults.apiKey),
      appId: _valueOrFallback(_macosAppId, defaults.appId),
      messagingSenderId: _valueOrFallback(
        _firebaseMessagingSenderId,
        defaults.messagingSenderId,
      ),
      projectId: _valueOrFallback(_firebaseProjectId, defaults.projectId),
      storageBucket: _valueOrFallback(
        _firebaseStorageBucket,
        defaults.storageBucket,
      ),
      iosBundleId: _valueOrFallback(_macosBundleId, defaults.iosBundleId),
    );
  }

  static FirebaseOptions get _windowsOptions {
    final defaults = DefaultFirebaseOptions.windows;
    return FirebaseOptions(
      apiKey: _valueOrFallback(_windowsApiKey, defaults.apiKey),
      appId: _valueOrFallback(_windowsAppId, defaults.appId),
      messagingSenderId: _valueOrFallback(
        _firebaseMessagingSenderId,
        defaults.messagingSenderId,
      ),
      projectId: _valueOrFallback(_firebaseProjectId, defaults.projectId),
      authDomain: _valueOrFallback(
        _windowsAuthDomain,
        defaults.authDomain,
      ),
      storageBucket: _valueOrFallback(
        _firebaseStorageBucket,
        defaults.storageBucket,
      ),
    );
  }

  static String _valueOrFallback(String rawValue, String? fallback) {
    if (rawValue.isNotEmpty) {
      return rawValue;
    }
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    throw StateError('Missing required Firebase configuration value.');
  }

  static Iterable<String> _parseCsv(String rawValue) {
    return rawValue
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
  }
}
