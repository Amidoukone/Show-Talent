import 'package:adfoot/services/users/block_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('blockUser / unblockUser', () {
    test('creates a doc id "{blockerUid}_{blockedUid}"', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BlockRepository(firestore: firestore);

      await repository.blockUser(blockerUid: 'a', blockedUid: 'b');

      final doc = await firestore.collection('blocks').doc('a_b').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['blockerUid'], 'a');
      expect(doc.data()!['blockedUid'], 'b');
      expect(doc.data()!['createdAt'], isNotNull);
    });

    test('unblocking removes only that directional doc', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BlockRepository(firestore: firestore);

      await repository.blockUser(blockerUid: 'a', blockedUid: 'b');
      await repository.blockUser(blockerUid: 'b', blockedUid: 'a');
      await repository.unblockUser(blockerUid: 'a', blockedUid: 'b');

      expect(
        (await firestore.collection('blocks').doc('a_b').get()).exists,
        isFalse,
      );
      expect(
        (await firestore.collection('blocks').doc('b_a').get()).exists,
        isTrue,
      );
    });
  });

  group('isBlockedEitherWay', () {
    test('true when the first uid blocked the second', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BlockRepository(firestore: firestore);
      await repository.blockUser(blockerUid: 'a', blockedUid: 'b');

      expect(await repository.isBlockedEitherWay('a', 'b'), isTrue);
      expect(await repository.isBlockedEitherWay('b', 'a'), isTrue);
    });

    test('false when no block exists between the two uids', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BlockRepository(firestore: firestore);
      await repository.blockUser(blockerUid: 'a', blockedUid: 'c');

      expect(await repository.isBlockedEitherWay('a', 'b'), isFalse);
    });
  });

  group('watchBlockedByMe / watchBlockingMe', () {
    test('each stream reflects only its own direction', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BlockRepository(firestore: firestore);

      await repository.blockUser(blockerUid: 'a', blockedUid: 'b');
      await repository.blockUser(blockerUid: 'c', blockedUid: 'a');

      final blockedByA = await repository.watchBlockedByMe('a').first;
      final blockingA = await repository.watchBlockingMe('a').first;

      expect(blockedByA, <String>{'b'});
      expect(blockingA, <String>{'c'});
    });
  });
}
