import 'package:adfoot/controller/block_controller.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/users/block_repository.dart';
import 'package:adfoot/services/users/user_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart' show ChatTestHarness;

BlockController _controller(
  FakeFirebaseFirestore firestore, {
  required String uid,
}) {
  return BlockController(
    blockRepository: BlockRepository(firestore: firestore),
    // idTokenChanges() is called unconditionally in onInit, and
    // AuthSessionService's own default constructor eagerly builds a
    // UserRepository() that reaches FirebaseFirestore.instance -- both
    // fakes are required to avoid a real, uninitialized Firebase app in a
    // pure Dart test.
    authSessionService: AuthSessionService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: '$uid@example.com'),
      ),
      userRepository: UserRepository(firestore: firestore),
    ),
    currentUidResolver: () => uid,
  );
}

void main() {
  setUpAll(ChatTestHarness.ensureFirebaseInitialized);

  group('blockUser / unblockUser optimistic update', () {
    test('blocking marks the target as blocked immediately', () async {
      final controller = _controller(FakeFirebaseFirestore(), uid: 'a');
      controller.onInit();

      final success = await controller.blockUser('b');

      expect(success, isTrue);
      expect(controller.isBlocked('b'), isTrue);
      expect(controller.isBlockedByMe('b'), isTrue);

      controller.onClose();
    });

    test('unblocking clears both isBlocked and isBlockedByMe', () async {
      final controller = _controller(FakeFirebaseFirestore(), uid: 'a');
      controller.onInit();

      await controller.blockUser('b');
      final success = await controller.unblockUser('b');

      expect(success, isTrue);
      expect(controller.isBlocked('b'), isFalse);
      expect(controller.isBlockedByMe('b'), isFalse);

      controller.onClose();
    });

    test('cannot block yourself', () async {
      final controller = _controller(FakeFirebaseFirestore(), uid: 'a');
      controller.onInit();

      final success = await controller.blockUser('a');

      expect(success, isFalse);
      expect(controller.isBlocked('a'), isFalse);

      controller.onClose();
    });
  });

  group('isBlocked union', () {
    test(
      'reflects a block made by someone else once the stream delivers it',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BlockRepository(firestore: firestore);
        await repository.blockUser(blockerUid: 'other', blockedUid: 'a');

        final controller = _controller(firestore, uid: 'a');
        controller.onInit();

        // Fake Firestore delivers its snapshot asynchronously; give the two
        // listeners set up in onInit a turn of the event loop to receive it.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.isBlocked('other'), isTrue);
        // Blocked *by* someone else, not blocked *by me* -- there is
        // nothing for an "Unblock" action on this side to undo.
        expect(controller.isBlockedByMe('other'), isFalse);

        controller.onClose();
      },
    );
  });
}
