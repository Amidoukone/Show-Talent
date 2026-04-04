import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'app_environment.dart';

class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _emulatorsConfigured = false;

  static Future<FirebaseApp> initialize() async {
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp(
            options: AppEnvironmentConfig.firebaseOptions,
          )
        : Firebase.app();

    await configureEmulatorsIfNeeded();

    if (kDebugMode) {
      debugPrint(
        '[FirebaseBootstrap] env=${AppEnvironmentConfig.environmentName} '
        'project=${AppEnvironmentConfig.firebaseProjectId} '
        'emulators=${AppEnvironmentConfig.useFirebaseEmulators}',
      );
    }

    return app;
  }

  static Future<void> configureEmulatorsIfNeeded() async {
    if (_emulatorsConfigured || !AppEnvironmentConfig.useFirebaseEmulators) {
      return;
    }

    final host = AppEnvironmentConfig.firebaseEmulatorHost;

    await FirebaseAuth.instance.useAuthEmulator(
      host,
      AppEnvironmentConfig.authEmulatorPort,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      AppEnvironmentConfig.firestoreEmulatorPort,
    );
    FirebaseFunctions.instanceFor(region: AppEnvironmentConfig.functionsRegion)
        .useFunctionsEmulator(
      host,
      AppEnvironmentConfig.functionsEmulatorPort,
    );
    FirebaseStorage.instance.useStorageEmulator(
      host,
      AppEnvironmentConfig.storageEmulatorPort,
    );

    _emulatorsConfigured = true;

    if (kDebugMode) {
      debugPrint(
        '[FirebaseBootstrap] Firebase emulators enabled on '
        '$host:${AppEnvironmentConfig.functionsEmulatorPort}',
      );
    }
  }
}
