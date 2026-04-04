import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class AccountCleanupException implements Exception {
  const AccountCleanupException({
    required this.message,
    this.requiresRecentLogin = false,
  });

  final String message;
  final bool requiresRecentLogin;

  @override
  String toString() => message;
}

/// Handles cascading cleanup for a user account.
class AccountCleanupService {
  AccountCleanupService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  static const Duration _maxDeleteAuthSessionAge = Duration(minutes: 20);

  /// Deletes user-owned data and user document, then optionally deletes Auth user.
  Future<void> deleteAccountAndData({
    required String uid,
    bool deleteAuthUser = false,
  }) async {
    if (deleteAuthUser) {
      _assertCanDeleteCurrentAuthUser(uid);
    }

    await _deleteVideos(uid);
    await _deleteOffres(uid);
    await _deleteEvents(uid);
    await _deleteConversations(uid);
    await _cleanupFollowReferences(uid);

    await _firestore.collection('users').doc(uid).delete();

    if (!deleteAuthUser) {
      return;
    }

    final current = _auth.currentUser;
    if (current == null || current.uid != uid) {
      return;
    }

    try {
      await current.delete();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login') {
        throw const AccountCleanupException(
          message:
              'Verification de securite requise. Merci de vous reconnecter puis de relancer la suppression.',
          requiresRecentLogin: true,
        );
      }

      throw AccountCleanupException(
        message:
            'Suppression du compte d\'authentification impossible (${error.code}).',
      );
    }
  }

  void _assertCanDeleteCurrentAuthUser(String uid) {
    final current = _auth.currentUser;
    if (current == null || current.uid != uid) {
      throw const AccountCleanupException(
        message: 'Session invalide. Veuillez vous reconnecter.',
      );
    }

    final lastSignIn = current.metadata.lastSignInTime;
    if (lastSignIn == null) {
      throw const AccountCleanupException(
        message:
            'Verification de securite requise. Merci de vous reconnecter puis de relancer la suppression.',
        requiresRecentLogin: true,
      );
    }

    final age = DateTime.now().difference(lastSignIn);
    if (age > _maxDeleteAuthSessionAge) {
      throw const AccountCleanupException(
        message:
            'Session de securite expiree. Merci de vous reconnecter puis de relancer la suppression.',
        requiresRecentLogin: true,
      );
    }
  }

  Future<void> _deleteVideos(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('videos')
          .where('uid', isEqualTo: uid)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        await _deleteStorageAsset(
          path: data['storagePath'] as String?,
          fallbackUrl: data['videoUrl'] as String?,
        );
        await _deleteStorageAsset(
          path: data['thumbnailPath'] as String?,
          fallbackUrl: data['thumbnail'] as String?,
        );

        await doc.reference.delete();
      }
    } catch (error) {
      debugPrint('AccountCleanup _deleteVideos error: $error');
    }
  }

  Future<void> _deleteOffres(String uid) async {
    try {
      final offres = await _firestore
          .collection('offres')
          .where('recruteur.uid', isEqualTo: uid)
          .get();

      for (final doc in offres.docs) {
        await doc.reference.delete();
      }
    } catch (error) {
      debugPrint('AccountCleanup _deleteOffres error: $error');
    }
  }

  Future<void> _deleteEvents(String uid) async {
    try {
      final events = await _firestore
          .collection('events')
          .where('organisateur.uid', isEqualTo: uid)
          .get();

      for (final doc in events.docs) {
        await doc.reference.delete();
      }
    } catch (error) {
      debugPrint('AccountCleanup _deleteEvents error: $error');
    }
  }

  Future<void> _deleteConversations(String uid) async {
    try {
      final conversations = await _firestore
          .collection('conversations')
          .where('utilisateurIds', arrayContains: uid)
          .get();

      for (final doc in conversations.docs) {
        final messages = await doc.reference.collection('messages').get();
        await _deleteDocsInChunks(
            messages.docs.map((m) => m.reference).toList());
        await doc.reference.delete();
      }
    } catch (error) {
      debugPrint('AccountCleanup _deleteConversations error: $error');
    }
  }

  Future<void> _cleanupFollowReferences(String uid) async {
    try {
      final followers = await _firestore
          .collection('users')
          .where('followersList', arrayContains: uid)
          .get();
      for (final doc in followers.docs) {
        await doc.reference.update({
          'followersList': FieldValue.arrayRemove([uid]),
        });
      }

      final followings = await _firestore
          .collection('users')
          .where('followingsList', arrayContains: uid)
          .get();
      for (final doc in followings.docs) {
        await doc.reference.update({
          'followingsList': FieldValue.arrayRemove([uid]),
        });
      }
    } catch (error) {
      debugPrint('AccountCleanup _cleanupFollowReferences error: $error');
    }
  }

  Future<void> _deleteStorageAsset({
    required String? path,
    required String? fallbackUrl,
  }) async {
    if ((path == null || path.isEmpty) &&
        (fallbackUrl == null || fallbackUrl.isEmpty)) {
      return;
    }

    try {
      if (path != null && path.isNotEmpty) {
        await _storage.ref(path).delete();
        return;
      }

      if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
        await _storage.refFromURL(fallbackUrl).delete();
      }
    } catch (_) {
      // Best-effort: assets can already be deleted.
    }
  }

  Future<void> _deleteDocsInChunks(List<DocumentReference> refs) async {
    const int chunkSize = 400; // Below 500 writes / batch limit.
    for (int i = 0; i < refs.length; i += chunkSize) {
      final chunk = refs.sublist(
        i,
        i + chunkSize > refs.length ? refs.length : i + chunkSize,
      );
      final batch = _firestore.batch();
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }
}
