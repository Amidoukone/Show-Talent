import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sprint 2 architecture guardrails', () {
    test('critical screens stay decoupled from direct Firebase SDK usage', () {
      const screenPaths = <String>[
        'lib/screens/chat_screen.dart',
        'lib/screens/event_form_screen.dart',
        'lib/screens/edit_profil_screen.dart',
      ];

      for (final path in screenPaths) {
        final content = File(path).readAsStringSync();
        expect(content, isNot(contains('cloud_firestore')));
        expect(content, isNot(contains('FirebaseFirestore')));
        expect(content, isNot(contains('FieldValue')));
      }
    });

    test('phase D shell screens do not instantiate controllers with Get.put',
        () {
      const phaseDScreenPaths = <String>[
        'lib/screens/main_screen.dart',
        'lib/screens/home_screen.dart',
        'lib/screens/select_user_screen.dart',
        'lib/screens/conversation_screen.dart',
        'lib/screens/video_feed_screen.dart',
        'lib/screens/profile_screen.dart',
        'lib/screens/profil_video_scrollview.dart',
        'lib/screens/profile_video_feed_screen.dart',
      ];

      for (final path in phaseDScreenPaths) {
        final content = File(path).readAsStringSync();
        expect(content, isNot(contains('Get.put(')));
      }
    });

    test('screens and widgets avoid ad hoc Get.put registration', () {
      final files = <File>[
        ...Directory('lib/screens')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
        ...Directory('lib/widgets')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
      ];

      for (final file in files) {
        final content = file.readAsStringSync();
        expect(content, isNot(contains('Get.put(')));
      }
    });

    test('Sprint 3 design system guardrails block legacy dialogs and snackbars',
        () {
      final screenFiles = Directory('lib/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      const allowedLegacyPaths = <String>{};
      const forbiddenPatterns = <String>[
        r'Get\.snackbar\s*\(',
        r'Get\.dialog\s*\(',
        r'showDialog\s*<',
        r'showDialog\s*\(',
        r'\bAlertDialog\b',
      ];

      for (final file in screenFiles) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (allowedLegacyPaths.contains(normalizedPath)) continue;

        final content = file.readAsStringSync();
        for (final pattern in forbiddenPatterns) {
          final regex = RegExp(pattern);
          expect(
            regex.hasMatch(content),
            isFalse,
            reason:
                'Forbidden legacy UI pattern "$pattern" found in $normalizedPath',
          );
        }
      }
    });

    test('Sprint 4 phase B upload form relies on controller states for loading',
        () {
      final content = File('lib/screens/upload_form.dart').readAsStringSync();
      expect(content, contains('isPreparing'));
      expect(content, isNot(contains('AdDialogs.showBlocking(')));
    });

    test(
        'Sprint 4 phase B video feed screen stays reactive and handles empty state',
        () {
      final content =
          File('lib/screens/video_feed_screen.dart').readAsStringSync();
      expect(content, contains('Obx(()'));
      expect(content, contains('Aucune video disponible'));
    });

    test('Sprint 4 phase C chat flow enforces single-send and no controller UI',
        () {
      final chatScreen =
          File('lib/screens/chat_screen.dart').readAsStringSync();
      final chatController =
          File('lib/controller/chat_controller.dart').readAsStringSync();

      expect(chatScreen, contains('if (content.isEmpty || _isSendingMessage)'));
      expect(chatScreen, contains('isSending: _isSendingMessage'));
      expect(chatController, isNot(contains('Get.snackbar(')));
      expect(chatController, contains('class ChatFlowException'));
    });

    test('Sprint 4 phase C account deletion requires reauthentication fallback',
        () {
      final settings =
          File('lib/screens/setting_screen.dart').readAsStringSync();
      final cleanup =
          File('lib/services/account_cleanup_service.dart').readAsStringSync();

      expect(settings, contains('_promptReauthenticationForDeletion'));
      expect(cleanup, contains('requiresRecentLogin'));
      expect(cleanup, contains('_assertCanDeleteCurrentAuthUser'));
    });

    test(
        'Sprint 4 phase D email link handler is test-safe and resilient to init failures',
        () {
      final emailHandler =
          File('lib/services/email_link_handler.dart').readAsStringSync();
      expect(emailHandler, contains('Get.testMode'));
      expect(emailHandler, contains('static bool _isInitializing = false;'));
      expect(emailHandler, contains('_initialized = false;'));
    });

    test('Sprint 4 phase D bootstrap and email handler avoid raw print logs',
        () {
      final bootstrap =
          File('lib/config/app_bootstrap.dart').readAsStringSync();
      final emailHandler =
          File('lib/services/email_link_handler.dart').readAsStringSync();

      expect(bootstrap, isNot(contains('print(')));
      expect(emailHandler, isNot(contains('print(')));
      expect(bootstrap, contains('debugPrint('));
    });
  });
}
