// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAo6Jr2eYrOTekjTHlJQXImr5q1UsI2jcA',
    appId: '1:43422248234:web:90e6e10558e53ab4f8c253',
    messagingSenderId: '43422248234',
    projectId: 'show-talent-5987d',
    authDomain: 'show-talent-5987d.firebaseapp.com',
    storageBucket: 'show-talent-5987d.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCbly653EeYnRWe70jzv3M2UJUCq03VJ-c',
    appId: '1:43422248234:android:08b0ab2b97c1f39ef8c253',
    messagingSenderId: '43422248234',
    projectId: 'show-talent-5987d',
    storageBucket: 'show-talent-5987d.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAtQdHtESNCw36DIJkEaPABzUvBWiX-XnI',
    appId: '1:43422248234:ios:5d961e9e382cbd4af8c253',
    messagingSenderId: '43422248234',
    projectId: 'show-talent-5987d',
    storageBucket: 'show-talent-5987d.appspot.com',
    iosBundleId: 'com.example.showTalent',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAtQdHtESNCw36DIJkEaPABzUvBWiX-XnI',
    appId: '1:43422248234:ios:5d961e9e382cbd4af8c253',
    messagingSenderId: '43422248234',
    projectId: 'show-talent-5987d',
    storageBucket: 'show-talent-5987d.appspot.com',
    iosBundleId: 'com.example.showTalent',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAo6Jr2eYrOTekjTHlJQXImr5q1UsI2jcA',
    appId: '1:43422248234:web:403c0fe305e9dedef8c253',
    messagingSenderId: '43422248234',
    projectId: 'show-talent-5987d',
    authDomain: 'show-talent-5987d.firebaseapp.com',
    storageBucket: 'show-talent-5987d.appspot.com',
  );
}
