import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// A Firestore snapshot subscription is finished once it delivers an error:
/// it never emits again. Every controller here guards its rebind on "is the
/// handle still null?", so holding a dead handle turns one transient failure
/// into a tab that never refreshes again for the rest of the session.
///
/// This is the symptom that was blamed, in a comment on `MainShellBinding`,
/// on GetX disposing route-scoped controllers. It was never that — those
/// controllers are registered permanent at bootstrap and GetX does not delete
/// a permanent instance with its route. It was this.
void main() {
  group('a dead watch releases its handle so something can rebind', () {
    test('offers: the guard that blocked every retry can be cleared', () {
      final offers = _read('lib/controller/offre_controller.dart');

      // The guard the stale handle defeated.
      expect(
        offers,
        contains('_offresSubscription != null &&'),
        reason: 'the rebind is conditional on the handle being null',
      );

      final watch = offers.indexOf('_offresSubscription = _offerRepository');
      expect(watch, isNonNegative);
      final onError = offers.indexOf('onError:', watch);
      expect(onError, isNonNegative);
      final body = offers.substring(onError, onError + 1400);
      expect(body, contains('_offresSubscription = null;'));
    });

    test('events: same guard, same release', () {
      final events = _read('lib/controller/event_controller.dart');

      expect(events, contains('_eventsSub != null &&'));

      // Anchored on the stream, not on the first onError in the file -- that
      // one belongs to the auth listener a few lines above.
      final watch = events.indexOf('_eventsSub = _eventRepository');
      expect(watch, isNonNegative);
      final onError = events.indexOf('onError:', watch);
      expect(onError, isNonNegative);
      final body = events.substring(onError, onError + 1400);
      expect(body, contains('_eventsSub = null;'));
    });

    // `_bindConversationsFor` returns early while `_convSub` is not null for
    // the same uid, so a stale handle froze the conversation list *and* the
    // unread badge in the navigation bar.
    test('chat: the conversation watch releases its handle', () {
      final chat = _read('lib/controller/chat_controller.dart');

      expect(chat, contains('if (_boundUid == userId && _convSub != null) {'));

      final watch = chat.indexOf('_convSub = _chatRepository');
      expect(watch, isNonNegative);
      final onError = chat.indexOf('onError:', watch);
      expect(onError, isNonNegative);
      expect(
        chat.substring(onError, onError + 1400),
        contains('_convSub = null;'),
      );
    });

    // Already fixed for the user directory; asserted here so the four watches
    // stay consistent with each other.
    test('users: the directory watch releases its handle', () {
      final users = _read('lib/controller/user_controller.dart');
      expect(users, contains('_usersSub = null;'));
      expect(users, contains("stage: 'directory_watch'"));
    });
  });

  group('a dead watch says so where it can be read', () {
    // AppLogger drops `debug` outright in a release build, and
    // `developer.log` writes to an attached debugger and nowhere else --
    // neither client_logs nor Crashlytics. On a tester's phone both produced
    // no record at all.
    test('the watches report at a level that survives a release build', () {
      expect(
        _read('lib/controller/offre_controller.dart'),
        contains("source: 'offers/watch'"),
      );
      expect(
        _read('lib/controller/event_controller.dart'),
        contains("source: 'events/watch'"),
      );
      expect(
        _read('lib/controller/chat_controller.dart'),
        contains("source: 'chat/conversation_watch'"),
      );
    });

    // The video feed is the odd one out: nothing is blocked by a stale
    // handle, because `listenToVideos` cancels and re-subscribes
    // unconditionally. The trouble is that `onInit` is its only caller, so
    // once the stream errors the feed receives no further live updates for
    // the session. Pull-to-refresh and pagination still work, which is why
    // it reads as degradation and went unnoticed.
    test('the video feed reports that it has gone static', () {
      final videos = _read('lib/controller/video_controller.dart');

      expect(videos, contains("source: 'videos/watch'"));
      expect(videos, contains('AppLogger.error('));
      expect(
        videos,
        isNot(contains("AppLogger.debug('Video stream error")),
        reason: 'release builds discard debug entirely',
      );
    });

    test('no watch failure is left to developer.log alone', () {
      final offers = _read('lib/controller/offre_controller.dart');

      final watch = offers.indexOf('_offresSubscription = _offerRepository');
      expect(watch, isNonNegative);
      final onError = offers.indexOf('onError:', watch);
      expect(onError, isNonNegative);
      final body = offers.substring(onError, onError + 1400);
      expect(
        body,
        isNot(contains('developer.log(')),
        reason: 'developer.log never leaves the device',
      );
      expect(body, contains('AppLogger.error('));
    });

    // The stream that drives all four. Nothing re-subscribes to it, so a
    // failure silently stops the app reacting to sign-in and sign-out.
    test('every auth listener reports, and under one stage', () {
      for (final path in const <String>[
        'lib/controller/user_controller.dart',
        'lib/controller/chat_controller.dart',
        'lib/controller/event_controller.dart',
        'lib/controller/offre_controller.dart',
      ]) {
        final source = _read(path);
        expect(
          source,
          contains("stage: 'auth_stream'"),
          reason: '$path stops following the session in silence',
        );
      }
    });
  });
}
