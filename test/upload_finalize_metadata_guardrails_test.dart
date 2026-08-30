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
      expect(
        uploadSession,
        contains('const alreadyLive = isLiveVideoDoc(currentDoc);'),
        reason: 'the liveness check must read the transaction snapshot',
      );
      // Line-ending agnostic: this file is CRLF on the authoring machine.
      final gate = uploadSession.indexOf('...(alreadyLive ? {} : {');
      expect(gate, isNonNegative);

      final gated = uploadSession.substring(gate, gate + 200);
      expect(gated, contains('moderationStatus: "pending",'));
      expect(gated, contains('visibility: "private",'));
      expect(gated, contains('isPublic: false,'));
    });

    // The mirror of the race above, and the regression that fixing it caused.
    //
    // Making a first finalize always write meant it could finally reach
    // resolveUploadLifecycleState with a document the optimizer had already
    // finished. That function only preserved "ready", so "under_review" --
    // exactly what optimizeMp4Video writes on success -- fell through to the
    // default and pushed a finished video back to processing/not-optimized,
    // where no admin could approve it. Seen in production on a 1.4 MB clip:
    // "Vidéo prête" logged at 23:38:58.200, overwritten at 23:38:58.992.
    test('a finished optimization is never pushed back to processing', () {
      final resolver =
          uploadSession.indexOf('function resolveUploadLifecycleState(');
      expect(resolver, isNonNegative);

      final body = uploadSession.substring(resolver, resolver + 1400);
      expect(body, contains('status === "under_review"'));
      expect(
        body,
        contains('return {status, optimized: true};'),
        reason: 'both terminal states must be preserved, not just "ready"',
      );
      expect(
        body,
        isNot(contains('return {status: "ready", optimized: true};')),
        reason: 'preserving only "ready" is what stranded the video',
      );
    });

    // Preserving both terminal states was necessary but not sufficient: the
    // resolver was reading the snapshot taken before validateVideoUpload and
    // validateThumbnail, two Storage round-trips and a ranged download. On a
    // light clip optimizeMp4Video commits inside that window, so the resolver
    // saw an empty document and the merge wrote `processing`/`optimized:false`
    // over a finished optimization. adminSetVideoStatus then refuses the
    // approval outright ("La video doit etre optimisee avant approbation"),
    // which is how a perfectly good upload becomes permanently un-approvable.
    //
    // adfoot-production, 2026-08-29: 9a9b1e2c and e40258a3 both hold the
    // optimizer's playback contract and download token — proof it finished —
    // with status `processing`.
    test('the lifecycle is decided on a document read in the transaction', () {
      expect(
        uploadSession,
        contains('await db.runTransaction(async (transaction) => {'),
      );

      final txn = uploadSession.indexOf(
        'let alreadyFinalized = false;',
      );
      expect(txn, isNonNegative);

      final body = uploadSession.substring(txn);
      final read = body.indexOf('await transaction.get(videoRef);');
      final resolve = body.indexOf(
        'const lifecycle = resolveUploadLifecycleState(currentDoc);',
      );
      final write = body.indexOf('transaction.set(');

      expect(read, isNonNegative, reason: 'the document must be re-read');
      expect(resolve, isNonNegative,
          reason: 'the resolver must be handed the transaction snapshot');
      expect(read, lessThan(resolve));
      expect(resolve, lessThan(write),
          reason: 'read, decide and write must share one transaction');

      expect(
        uploadSession,
        isNot(contains('const lifecycle = resolveUploadLifecycleState(doc);')),
        reason: 'deciding on the pre-validation snapshot is the whole bug',
      );
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
