import 'package:adfoot/services/app_logger.dart';
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
  ///
  /// Advisory, never authoritative, and deliberately unable to fail the
  /// caller. The block that matters is enforced by `firestore.rules` on the
  /// conversation and message writes themselves (`isBlockedPair`), and the
  /// reactive view the UI reads comes from `BlockController`'s two
  /// directional queries. This is only the pre-flight courtesy check that
  /// turns "write refused" into a sentence the user can understand.
  ///
  /// It used to let a failed read escape. Almost every call asks about a pair
  /// that is *not* blocked, so the documents it reads almost never exist —
  /// and a `get` on a missing document is refused by any rule that reads
  /// `resource.data`, which is exactly what the rule did. The result was a
  /// permission-denied on the happy path of every conversation start and
  /// every send: messaging stopped working app-wide, reported only as
  /// "impossible de démarrer la conversation". The rule is fixed too (see the
  /// `blocks` get rule), but this must not depend on a rules deploy having
  /// landed: an unanswerable pre-check means "nothing known against it", and
  /// the write that follows is still refused server-side if a block is real.
  Future<bool> isBlockedEitherWay(String uidA, String uidB) async {
    final results = await Future.wait([
      _blockExists(_blockId(uidA, uidB)),
      _blockExists(_blockId(uidB, uidA)),
    ]);
    return results.any((exists) => exists);
  }

  Future<bool> _blockExists(String blockId) async {
    try {
      final doc = await _blocksCollection.doc(blockId).get();
      return doc.exists;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'block pre-check unavailable for $blockId; treating the pair as not '
        'blocked and leaving the decision to the Firestore rules',
        source: 'BlockRepository._blockExists',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
