import 'package:adfoot/l10n/video_ui_translations.dart';
import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  // AuthErrorMapper resolves through GetX's `.tr`, which needs
  // Get.locale/Get.translations populated -- set directly (no widget to
  // pump in a pure test) so the assertions below check real French text,
  // not `.tr` silently falling back to the bare key.
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(VideoUiTranslations().keys);
    Get.locale = const Locale('fr');
    Get.fallbackLocale = const Locale('fr');
  });
  tearDown(() {
    Get.clearTranslations();
    Get.reset();
  });

  group('AuthErrorMapper', () {
    test(
      'maps CONFIGURATION_NOT_FOUND to an actionable environment message',
      () {
        final error = FirebaseAuthException(
          code: 'internal-error',
          message:
              'An internal error has occurred. [ CONFIGURATION_NOT_FOUND ]',
        );

        final message = AuthErrorMapper.toMessage(error);

        expect(message, contains('Firebase Authentication'));
        expect(message, contains('Email/Password'));
      },
    );
  });
}
