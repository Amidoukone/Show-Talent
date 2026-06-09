import 'dart:convert';
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

    test('screens avoid direct Firestore, Storage and Functions access', () {
      final offenders = <String>[];
      final files = Directory('lib/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      const forbiddenPatterns = <String>[
        'cloud_firestore',
        'FirebaseFirestore',
        'firebase_storage',
        'FirebaseStorage',
        'cloud_functions',
        'FirebaseFunctions',
      ];

      for (final file in files) {
        final content = file.readAsStringSync();
        for (final pattern in forbiddenPatterns) {
          if (content.contains(pattern)) {
            offenders.add('${file.path}: $pattern');
          }
        }
      }

      expect(offenders, isEmpty);
    });

    test('profile and offer controllers keep Firebase access in repositories',
        () {
      final profileController =
          File('lib/controller/profile_controller.dart').readAsStringSync();
      final offerController =
          File('lib/controller/offre_controller.dart').readAsStringSync();
      final profileRepository =
          File('lib/services/users/profile_repository.dart').readAsStringSync();
      final offerRepository =
          File('lib/services/offers/offer_repository.dart').readAsStringSync();

      for (final controller in <String>[profileController, offerController]) {
        expect(controller, isNot(contains('cloud_firestore')));
        expect(controller, isNot(contains('firebase_storage')));
        expect(controller, isNot(contains('FirebaseFirestore')));
        expect(controller, isNot(contains('FirebaseStorage')));
        expect(controller, isNot(contains('collection(')));
        expect(controller, isNot(contains('runTransaction(')));
      }

      expect(profileController, contains('_profileRepository.'));
      expect(offerController, contains('_offerRepository.'));
      expect(profileRepository, contains("collection('users')"));
      expect(profileRepository, contains("collection('videos')"));
      expect(offerRepository, contains("collection('offres')"));
    });

    test('video upload and follow controllers keep Firebase access in services',
        () {
      final videoController =
          File('lib/controller/video_controller.dart').readAsStringSync();
      final uploadController =
          File('lib/controller/upload_video_controller.dart')
              .readAsStringSync();
      final followController =
          File('lib/controller/follow_controller.dart').readAsStringSync();
      final videoRepository =
          File('lib/services/videos/video_repository.dart').readAsStringSync();
      final videoActionService =
          File('lib/services/videos/video_action_service.dart')
              .readAsStringSync();
      final uploadRepository =
          File('lib/services/videos/upload_video_repository.dart')
              .readAsStringSync();
      final followRepository =
          File('lib/services/users/follow_repository.dart').readAsStringSync();

      const forbiddenControllerPatterns = <String>[
        'cloud_firestore',
        'firebase_storage',
        'cloud_functions',
        'firebase_auth',
        'FirebaseFirestore',
        'FirebaseStorage',
        'FirebaseFunctions',
        'FirebaseAuth',
        'FieldValue',
        'runTransaction(',
        'collection(',
      ];

      for (final controller in <String>[
        videoController,
        uploadController,
        followController,
      ]) {
        for (final pattern in forbiddenControllerPatterns) {
          expect(controller, isNot(contains(pattern)));
        }
      }

      expect(videoController, contains('_videoRepository.'));
      expect(videoController, contains('_videoActionService.'));
      expect(uploadController, contains('_uploadRepository.'));
      expect(uploadController, contains('UploadVideoErrorMapper.'));
      expect(followController, contains('_followRepository.'));
      expect(videoRepository, contains("collection('videos')"));
      expect(videoRepository, contains('runTransaction<ActionResponse>'));
      expect(videoActionService, contains('FirebaseFunctions.instanceFor'));
      expect(uploadRepository, contains("collection('videos')"));
      expect(uploadRepository, contains('FirebaseStorage.instance'));
      expect(followRepository, contains("collection('users')"));
      expect(followRepository, contains('FirebaseFunctions.instanceFor'));
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

    test('production feedback uses the shared AdFeedback channel', () {
      const forbiddenPatterns = <String>[
        r'Get\.snackbar\s*\(',
        r'Get\.showSnackbar\s*\(',
        r'Get\.closeCurrentSnackbar\s*\(',
        r'Get\.isSnackbarOpen\b',
        r'\bGetSnackBar\b',
        r'ScaffoldMessenger\.of\s*\(',
        r'\.showSnackBar\s*\(',
        r'\bSnackBar\s*\(',
      ];

      final offenders = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        final content = file.readAsStringSync();
        for (final pattern in forbiddenPatterns) {
          if (RegExp(pattern).hasMatch(content)) {
            offenders.add('$normalizedPath: $pattern');
          }
        }
      }

      expect(offenders, isEmpty);
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
      expect(content, contains('VideoUiStrings.emptyVideoFeedTitle'));
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
      expect(bootstrap, contains('AppLogger.debug('));
    });

    test('production lib code routes debug traces through AppLogger', () {
      final offenders = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (normalizedPath == 'lib/services/app_logger.dart') {
          continue;
        }
        final content = file.readAsStringSync();
        if (content.contains('debugPrint(')) {
          offenders.add(normalizedPath);
        }
      }

      expect(offenders, isEmpty);
    });

    test('production lib code avoids raw print logs', () {
      final offenders = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final content = file.readAsStringSync();
        if (content.contains('print(')) {
          offenders.add(file.path);
        }
      }

      expect(offenders, isEmpty);
    });

    test('functions package stays deploy-scoped and on the maintained runtime',
        () {
      final rootPackage = jsonDecode(File('package.json').readAsStringSync())
          as Map<String, dynamic>;
      final functionsPackage =
          jsonDecode(File('functions/package.json').readAsStringSync())
              as Map<String, dynamic>;

      final rootDependencies =
          (rootPackage['dependencies'] as Map).cast<String, dynamic>();
      final functionsDependencies =
          (functionsPackage['dependencies'] as Map).cast<String, dynamic>();
      final functionsDevDependencies =
          (functionsPackage['devDependencies'] as Map).cast<String, dynamic>();
      final functionsEngines =
          (functionsPackage['engines'] as Map).cast<String, dynamic>();

      expect(rootDependencies.keys, unorderedEquals(['firebase-admin']));
      expect(functionsDependencies, isNot(contains('adfoot')));
      expect(functionsDependencies['firebase-admin'], startsWith('^13.'));
      expect(functionsDependencies['firebase-functions'], startsWith('^7.'));
      expect(functionsDevDependencies['typescript'], startsWith('^5.'));
      expect(functionsEngines['node'], '22');
    });
  });
}
