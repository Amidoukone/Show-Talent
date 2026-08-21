import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// finalizeUpload is the only writer of description, caption and duration.
///
/// It declared itself a duplicate whenever the *optimizer* had finished --
/// `optimized === true && status in (ready, under_review)`, which is exactly
/// the state optimizeMp4Video writes -- and then wrote nothing while returning
/// {ok: true}. The two are independent, and the upload flow races them: the
/// client uploads the video, which starts the optimizer, then the thumbnail,
/// and only then calls finalizeUpload.
///
/// On a light clip the optimizer won. adfoot-production held two videos from
/// 2026-08-21, both ready/approved/public, with description, caption and
/// duration never written -- legacy aliases included. On a heavy clip the
/// client won and the text was there, which is what made it read as "the text
/// is missing, except when the video is heavy".
String _read(String path) => File(path).readAsStringSync();

void main() {
  late String uploadSession;

  setUpAll(() {
    uploadSession = _read('functions/src/upload_session.ts');
  });

  group('the owner metadata is written exactly once, and never lost', () {
    test('finalization is its own marker, not the optimizer state', () {
      expect(
        uploadSession,
        contains(
          'return doc?.finalizedAt !== undefined && doc?.finalizedAt !== null;',
        ),
      );
      expect(
        uploadSession,
        isNot(contains('return doc?.optimized === true &&')),
        reason: 'the optimizer finishing says nothing about the owner metadata',
      );
    });

    test('the marker is written by the call it describes', () {
      expect(
        uploadSession,
        contains('finalizedAt: fieldValue.serverTimestamp(),'),
      );
    });

    // The protection was never the error, it was not writing. A retry still
    // writes nothing.
    test('a retry is still an idempotent no-op', () {
      expect(uploadSession, contains('alreadyFinalized: true'));
      expect(
        uploadSession,
        contains('if (isFinalizedUploadSession(doc)) {'),
      );
    });

    // A legacy document carries no finalizedAt, so it can now reach the write.
    // Sending an approved, public video back to pending would unpublish it --
    // the regression c404c95 fixed, previously prevented only as a side effect
    // of refusing to run at all.
    test('an already published video is never downgraded', () {
      expect(uploadSession, contains('function isLiveVideoDoc('));
      expect(uploadSession, contains('const alreadyLive = isLiveVideoDoc(doc);'));
      // Line-ending agnostic: this file is CRLF on the authoring machine.
      final gate = uploadSession.indexOf('...(alreadyLive ? {} : {');
      expect(gate, isNonNegative);

      final gated = uploadSession.substring(gate, gate + 200);
      expect(gated, contains('moderationStatus: "pending",'));
      expect(gated, contains('visibility: "private",'));
      expect(gated, contains('isPublic: false,'));
    });

    test('the canonical and legacy aliases are still both written', () {
      expect(
        uploadSession,
        contains('...(safe.description ? {description: safe.description} : {}),'),
      );
      expect(
        uploadSession,
        contains('songName: safe.description, title: safe.description'),
      );
      expect(
        uploadSession,
        contains('legend: safe.caption, legende: safe.caption'),
      );
    });
  });
}
