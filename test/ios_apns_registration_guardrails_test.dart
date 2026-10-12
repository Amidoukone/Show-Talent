import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pourquoi aucun iPhone n'a jamais recu de notification.
///
/// La chaine iOS tient a un seul appel, `registerForRemoteNotifications`, et
/// personne ne le faisait.
///
/// `FLTFirebaseMessagingPlugin` le fait normalement, depuis son observateur de
/// `UIApplicationDidFinishLaunchingNotification`, mais derriere une garde :
/// `if ([FIRMessaging messaging].isAutoInitEnabled)`. Cette garde exige une
/// application Firebase par defaut deja configuree. Or sur iOS, `firebase_core`
/// n'en configure une nativement que si `[FIROptions defaultOptions]` trouve un
/// `GoogleService-Info.plist` **dans le bundle**. Celui de cette application
/// n'y est pas : la configuration passe par `--dart-define` et
/// `Firebase.initializeApp()` cote Dart, donc elle n'existe pas encore au
/// lancement. `[FIRMessaging messaging]` vaut nil, `nil.isAutoInitEnabled`
/// vaut NO, l'enregistrement est saute -- et jamais repris : la mise en place
/// n'a lieu qu'une fois et `didReinitializeFirebaseCore` ne fait rien.
///
/// Sans cet appel, iOS ne contacte jamais Apple : pas de jeton d'appareil,
/// `getAPNSToken()` rend nil indefiniment, `getToken()` leve
/// `apns-token-not-set` indefiniment, et `user_push_tokens` n'a jamais contenu
/// une seule entree iOS pendant qu'Android fonctionnait.
///
/// Ces tests gardent les deux moities de la cause : l'appel est la, et la
/// raison pour laquelle il doit y etre -- l'absence de plist dans le bundle --
/// est toujours vraie. Si un jour le plist y est ajoute, le second test
/// echouera, et c'est voulu : la justification aura change.
void main() {
  group('iOS demande son jeton APNs lui-meme', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    test('AppDelegate appelle registerForRemoteNotifications', () {
      expect(
        appDelegate,
        contains('registerForRemoteNotifications()'),
        reason: 'sans cet appel aucun jeton APNs n\'existe, donc aucun jeton '
            'FCM, donc aucune notification iOS',
      );
    });

    test('il est appele apres l\'enregistrement des plugins', () {
      final register = appDelegate.indexOf('GeneratedPluginRegistrant.register');
      final apns = appDelegate.indexOf('registerForRemoteNotifications()');
      expect(register, isNonNegative);
      expect(apns, greaterThan(register));
    });

    test('il est differe d\'un tour de boucle', () {
      // Le plugin s'installe comme intercepteur APNs depuis la *notification*
      // DidFinishLaunching, que UIKit poste apres le retour de cette methode.
      // Appeler en ligne lancerait l'aller-retour avant que l'intercepteur
      // existe.
      final apns = appDelegate.indexOf('registerForRemoteNotifications()');
      expect(
        appDelegate.substring(apns < 200 ? 0 : apns - 200, apns),
        contains('DispatchQueue.main.async'),
      );
    });

    test('aucun GoogleService-Info.plist n\'est embarque dans le bundle', () {
      // C'est la raison d'etre de l'appel ci-dessus. Tant que c'est vrai,
      // firebase_core ne configure rien nativement et la garde du plugin ne
      // peut pas passer.
      final project =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(
        project.contains('GoogleService-Info.plist'),
        isFalse,
        reason: 'si le plist est embarque, firebase_core configure '
            'l\'application par defaut au lancement et la garde du plugin '
            'passe : le commentaire de AppDelegate.swift doit alors etre revu',
      );
    });

    test('l\'entitlement APNs est cable pour chaque configuration', () {
      // L'appel ne sert a rien si la signature ne porte pas aps-environment :
      // iOS repond didFailToRegisterForRemoteNotificationsWithError.
      for (final name in const [
        'ios/Flutter/Debug.xcconfig',
        'ios/Flutter/Release.xcconfig',
        'ios/Flutter/Release-staging.xcconfig',
        'ios/Flutter/Release-production.xcconfig',
      ]) {
        expect(
          File(name).readAsStringSync(),
          contains('CODE_SIGN_ENTITLEMENTS='),
          reason: '$name ne designe aucun fichier d\'entitlements',
        );
      }

      // Et les builds distribues demandent l'environnement de production,
      // le seul que joint une signature Distribution.
      for (final name in const [
        'ios/Flutter/Release-staging.xcconfig',
        'ios/Flutter/Release-production.xcconfig',
      ]) {
        expect(
          File(name).readAsStringSync(),
          contains('Runner-Distribution.entitlements'),
        );
      }
      expect(
        File('ios/Runner/Runner-Distribution.entitlements').readAsStringSync(),
        contains('<string>production</string>'),
      );
    });
  });
}
