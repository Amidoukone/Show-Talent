import 'package:cloud_firestore/cloud_firestore.dart';

/// One doc per directional block, id "{blockerUid}_{blockedUid}". No Cloud
/// Function in front of it: a single-doc create/delete with no
/// cross-document counter doesn't need the transactional Admin SDK writes
/// that follow (followersList/followingsList + counts on two other docs)
/// requires -- a rules-gated client write is enough, same shape as
/// contact_intakes.
class BlockRepository {
  BlockRepository({FirebaseFirestore? firestore}) : _injected = firestore;

  // Resolved lazily, not in the initializer list: FirebaseFirestore.instance
  // throws until a Firebase app exists, and this repository is constructed
  // as ChatRepository's default dependency -- eagerly reaching it would
  // demand a live Firebase app just to build a ChatRepository, even in a
  // test that never touches blocking at all. Same fix as
  // FollowRepository's own _firestore getter, same reason.
  final FirebaseFirestore? _injected;

  FirebaseFirestore get _firestore => _injected ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _blocksCollection =>
      _firestore.collection('blocks');

  static String _blockId(String blockerUid, String blockedUid) =>
      '${blockerUid}_$blockedUid';

  Future<void> blockUser({
    required String blockerUid,
    required String blockedUid,
  }) {
    return _blocksCollection.doc(_blockId(blockerUid, blockedUid)).set({
      'blockerUid': blockerUid,
      'blockedUid': blockedUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblockUser({
    required String blockerUid,
    required String blockedUid,
  }) {
    return _blocksCollection.doc(_blockId(blockerUid, blockedUid)).delete();
  }

  Stream<Set<String>> watchBlockedByMe(String uid) {
    return _blocksCollection
        .where('blockerUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => doc.data()['blockedUid']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet(),
        );
  }

  Stream<Set<String>> watchBlockingMe(String uid) {
    return _blocksCollection
        .where('blockedUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => doc.data()['blockerUid']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet(),
        );
  }

  /// Whether either uid has blocked the other, in either direction.
  Future<bool> isBlockedEitherWay(String uidA, String uidB) async {
    final results = await Future.wait([
      _blocksCollection.doc(_blockId(uidA, uidB)).get(),
      _blocksCollection.doc(_blockId(uidB, uidA)).get(),
    ]);
    return results.any((doc) => doc.exists);
  }
}
