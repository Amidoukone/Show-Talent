import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The feed is ordered by when a video became public, not by when its
/// document was last touched.
///
/// `updatedAt` moves on any admin write — `adminSetVideoStatus` stamps it on
/// hide, on re-approve, on every moderation pass — so a video hidden and put
/// back six months later would re-enter at the top of the feed and be
/// announced as a new video. `approvedAt` is written once, by the same
/// transaction that sets `status: ready`, which is the only path to that
/// status: every ready video has one, so none can fall out of the ordering.
///
/// On adfoot-production the two fields held the same instant on all fourteen
/// ready documents (2026-08-24), so the change is invisible today and only
/// matters the first time a video is re-moderated.
void main() {
  late String repository;

  setUpAll(() {
    repository = _read('lib/services/videos/video_repository.dart');
  });

  test('both feed queries order by approvedAt', () {
    expect(repository, contains("static const String _feedOrderField = 'approvedAt';"));
    expect(
      repository,
      isNot(contains(".orderBy('updatedAt', descending: true)")),
      reason: 'the ordering key must come from the constant, not a literal',
    );

    final query = repository.indexOf('Query<Map<String, dynamic>> _readyVideosQuery(');
    expect(query, isNonNegative);
    expect(
      repository.substring(query, query + 400),
      contains(".orderBy(orderField, descending: true)"),
    );
  });

  // The composite index (status ASC, approvedAt DESC) did not exist in
  // adfoot-production when this shipped, and a Firestore index is not instant
  // even once deployed: it builds, and the query fails `failed-precondition`
  // until it is ready. Coupling the release to the deploy means an empty home
  // screen for everyone if the order is wrong.
  test('a missing index downgrades instead of emptying the feed', () {
    expect(repository, contains("static const String _legacyOrderField = 'updatedAt';"));
    expect(repository, contains('static bool _isMissingIndex(Object error)'));
    expect(repository, contains("error.code == 'failed-precondition'"));
    expect(repository, contains('void _downgradeOrderField()'));

    // The paginated read retries the same page on the fallback field.
    final page = repository.indexOf('Future<VideoFeedPage> fetchReadyVideosPage(');
    expect(page, isNonNegative);
    final pageBody = repository.substring(page, page + 900);
    expect(pageBody, contains('_downgradeOrderField();'));
    expect(pageBody, contains('orderField: _legacyOrderField,'));

    // And the live stream resubscribes rather than surfacing the error.
    final watch = repository.indexOf('Stream<VideoLiveBatch> watchReadyVideos(');
    expect(watch, isNonNegative);
    final watchBody = repository.substring(watch, watch + 1200);
    expect(watchBody, contains('subscribe(_legacyOrderField);'));
    expect(
      watchBody.indexOf('subscribe(_legacyOrderField);'),
      lessThan(watchBody.indexOf('controller.addError(error, stackTrace);')),
      reason: 'the fallback is tried before the error reaches the controller',
    );
  });

  // A query that orders by a field is blind to documents missing it, so the
  // index has to exist for the deploy to be the whole fix.
  test('the composite index ships with the query', () {
    final indexes = _read('firestore.indexes.json');
    expect(indexes, contains('"approvedAt"'));

    final approved = indexes.indexOf('"approvedAt"');
    final block = indexes.substring(
      (approved - 400).clamp(0, indexes.length),
      approved,
    );
    expect(block, contains('"videos"'));
    expect(block, contains('"status"'));
  });
}
