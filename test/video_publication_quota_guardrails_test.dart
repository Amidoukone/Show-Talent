import 'dart:io';

import 'package:adfoot/services/videos/upload_video_error_mapper.dart';
import 'package:adfoot/services/videos/upload_video_repository.dart';
import 'package:adfoot/utils/video_publication_quota.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// A player at their publication cap used to find out the hard way.
///
/// adfoot-production, `client_logs`, 2026-08-22 at 09:17:34 and again at
/// 09:17:52: `code: "resource-exhausted"`, `stage: "Initialisation..."`,
/// `progress: 0.18`. The clip had already been chosen, trimmed, thumbnailed
/// and started uploading before `createUploadSession` refused it — twice,
/// because the message it gave back ("Archivez une video avant d'en ajouter
/// une nouvelle") asks for something this application offers no way to do, so
/// the only thing left to try was the same button again. The account held
/// exactly ten `ready` videos.
String _read(String path) => File(path).readAsStringSync();

/// The exact text `assertUploadRateLimits` returns today: ASCII, no accents.
const String _productionQuotaMessage =
    "Vous avez deja 10 videos publiques. Archivez une video avant d'en "
    'ajouter une nouvelle.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the client cap agrees with the server cap', () {
    test('MAX_PUBLIC_PLAYER_VIDEOS and maxPublishedVideos are the same number',
        () {
      final uploadSession = _read('functions/src/upload_session.ts');
      final match = RegExp(
        r'const MAX_PUBLIC_PLAYER_VIDEOS = parsePositiveIntEnv\(\s*'
        r'process\.env\.MAX_PUBLIC_PLAYER_VIDEOS,\s*(\d+),',
      ).firstMatch(uploadSession);

      expect(
        match,
        isNotNull,
        reason: 'the server default is the number the client mirrors',
      );
      expect(
        int.parse(match!.group(1)!),
        VideoPublicationQuota.maxPublishedVideos,
        reason: 'a client that guesses a different cap either blocks uploads '
            'the server would have accepted, or promises ones it will refuse',
      );
    });
  });

  group('the refusal is recognised and rewritten', () {
    FirebaseFunctionsException exhausted(String message,
        {Object? details}) {
      return FirebaseFunctionsException(
        code: 'resource-exhausted',
        message: message,
        details: details,
      );
    }

    test('the deployed accent-free wording is recognised', () {
      expect(
        UploadVideoErrorMapper.isPublicVideoQuotaFailure(
          exhausted(_productionQuotaMessage),
        ),
        isTrue,
      );
    });

    test('a properly accented rewording of it is recognised too', () {
      expect(
        UploadVideoErrorMapper.isPublicVideoQuotaFailure(
          exhausted('Vous avez déjà 10 vidéos publiques.'),
        ),
        isTrue,
      );
    });

    test('structured details win over prose', () {
      expect(
        UploadVideoErrorMapper.isPublicVideoQuotaFailure(
          exhausted('', details: {'reason': 'public_video_quota'}),
        ),
        isTrue,
      );
    });

    // assertUploadRateLimits raises resource-exhausted for four different
    // refusals plus the upload kill switch. Only one of them is answered by
    // asking the agency to raise a cap.
    test('the other resource-exhausted refusals are left alone', () {
      const others = <String>[
        "Trop d'uploads video sont deja en cours pour ce compte.",
        "Limite quotidienne d'upload video atteinte.",
        'Vous avez deja 3 videos en revue admin.',
        'Les uploads vidéo sont temporairement désactivés.',
      ];

      for (final message in others) {
        expect(
          UploadVideoErrorMapper.isPublicVideoQuotaFailure(
            exhausted(message),
          ),
          isFalse,
          reason: message,
        );
        expect(
          UploadVideoErrorMapper.toUserMessage(exhausted(message)),
          message,
          reason: 'these already say something the user can act on',
        );
      }
    });

    test('a different code is never a quota refusal', () {
      expect(
        UploadVideoErrorMapper.isPublicVideoQuotaFailure(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Vous avez deja 10 videos publiques.',
          ),
        ),
        isFalse,
      );
    });

    test('the user is told to ask the agency, not to archive', () {
      final shown = UploadVideoErrorMapper.toUserMessage(
        exhausted(_productionQuotaMessage),
      );

      expect(
        shown,
        VideoUiStrings.uploadQuotaReachedShort(
          VideoPublicationQuota.maxPublishedVideos,
        ),
      );
      expect(shown, contains('Adfoot'));
      expect(shown, contains('10'));
      expect(
        shown.toLowerCase(),
        isNot(contains('archiv')),
        reason: 'nothing in the application archives a video',
      );
    });
  });

  group('the cap is checked before any work is asked of the user', () {
    test('countPublishedVideos counts this account\'s ready videos only',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = UploadVideoRepository(firestore: firestore);

      for (var index = 0; index < 10; index++) {
        await firestore.collection('videos').doc('mine-$index').set({
          'uid': 'player-1',
          'status': 'ready',
        });
      }
      // Neither of these is a published video of this player's.
      await firestore.collection('videos').doc('mine-processing').set({
        'uid': 'player-1',
        'status': 'under_review',
      });
      await firestore.collection('videos').doc('someone-else').set({
        'uid': 'player-2',
        'status': 'ready',
      });

      expect(await repository.countPublishedVideos('player-1'), 10);
      expect(await repository.countPublishedVideos('player-2'), 1);
      expect(await repository.countPublishedVideos('nobody'), 0);
    });

    test('the picker asks before it opens the gallery', () {
      final addVideo = _read('lib/screens/add_video.dart');

      final pick = addVideo.indexOf('Future<void> _pickVideoFromGallery()');
      expect(pick, isNonNegative);
      final body = addVideo.substring(pick);

      final check = body.indexOf('checkPublicationQuota()');
      final picker = body.indexOf('_picker.pickVideo(');
      expect(check, isNonNegative);
      expect(picker, isNonNegative);
      expect(
        check,
        lessThan(picker),
        reason: 'the whole point is not to make the user trim a clip that '
            'cannot be published',
      );
      expect(body, contains('VideoPublicationQuotaState.exhausted'));
      expect(body, contains('_showPublicationQuotaNotice()'));
    });

    // A failed count is not a refusal. Blocking on one would turn a flaky
    // Firestore read into "you may not publish", which is a worse bug than
    // the one the check exists to prevent.
    test('an unreadable count lets the flow continue', () {
      final controller = _read('lib/controller/upload_video_controller.dart');

      final start = controller.indexOf(
        'Future<VideoPublicationQuotaState> checkPublicationQuota()',
      );
      expect(start, isNonNegative);
      final body = controller.substring(
        start,
        controller.indexOf('\n  }', start),
      );

      expect(body, contains('return VideoPublicationQuotaState.unknown;'));
      expect(body, contains('} catch (error, stackTrace) {'));
    });

    test('the notice offers the agency, and a readable fallback', () {
      final addVideo = _read('lib/screens/add_video.dart');

      expect(addVideo, contains('AdfootSupport.openWhatsApp()'));
      expect(addVideo, contains('VideoUiStrings.uploadQuotaContactFallback('));
      expect(
        VideoUiStrings.uploadQuotaContactAction,
        contains('Adfoot'),
      );
      expect(
        VideoUiStrings.uploadQuotaReachedMessage(10),
        contains('Adfoot'),
      );
      expect(
        VideoUiStrings.uploadQuotaContactFallback('+223 70 45 33 45', 'adfoot.org'),
        contains('+223 70 45 33 45'),
      );
    });
  });
}
