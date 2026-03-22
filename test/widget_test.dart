import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:get/get.dart';

import 'package:adfoot/main.dart';
import 'package:adfoot/screens/splash_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:adfoot/services/email_link_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'test-api-key',
          appId: '1:1234567890:android:test',
          messagingSenderId: '1234567890',
          projectId: 'test-project',
          storageBucket: 'test-project.appspot.com',
        ),
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  });

  setUp(() {
    Get.testMode = true;
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('Bootstrap Firebase mocké disponible',
      (WidgetTester tester) async {
    expect(Firebase.apps, isNotEmpty);
    expect(const MyApp(), isA<MyApp>());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('firebase-mock-ready')),
      ),
    );
    expect(find.text('firebase-mock-ready'), findsOneWidget);
  });

  testWidgets('SplashScreen route vers un fallback controle',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: SplashScreen(
          fallbackInitializationDelay: Duration.zero,
          fallbackRouteBuilder: () async => const Scaffold(
            body: Center(
              child: Text('mock-fallback-destination'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('mock-fallback-destination'), findsOneWidget);
  });

  testWidgets('SplashScreen route vers VerifyEmailScreen en fallback controle',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: SplashScreen(
          fallbackInitializationDelay: Duration.zero,
          fallbackRouteBuilder: () async => const VerifyEmailScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(VerifyEmailScreen), findsOneWidget);

    // Nettoyage explicite pour éviter des timers pendants en fin de test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await EmailLinkHandler.dispose();
    await tester.pump(const Duration(seconds: 6));
  });
}
