import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Gère la suppression en cascade des données liées à un utilisateur.
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

  /// Supprime les contenus et références du [uid], puis le document utilisateur.
  /// Peut aussi supprimer le compte Firebase Auth associé.
  Future<void> deleteAccountAndData({
    required String uid,
    bool deleteAuthUser = false,
  }) async {
    await _deleteVideos(uid);
    await _deleteOffres(uid);
    await _deleteEvents(uid);
    await _deleteConversations(uid);
    await _cleanupFollowReferences(uid);

    await _firestore.collection('users').doc(uid).delete();

    if (deleteAuthUser) {
      final current = _auth.currentUser;
      if (current != null && current.uid == uid) {
        await current.delete();
      }
    }
  }

  Future<void> _deleteVideos(String uid) async {
    try {
      final snapshot =
          await _firestore.collection('videos').where('uid', isEqualTo: uid).get();

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
    } catch (e) {
      debugPrint('❌ _deleteVideos error: $e');
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
    } catch (e) {
      debugPrint('❌ _deleteOffres error: $e');
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
    } catch (e) {
      debugPrint('❌ _deleteEvents error: $e');
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
        await _deleteDocsInChunks(messages.docs.map((m) => m.reference).toList());
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('❌ _deleteConversations error: $e');
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
    } catch (e) {
      debugPrint('❌ _cleanupFollowReferences error: $e');
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
      // Les assets peuvent déjà être supprimés : on ignore silencieusement.
    }
  }

  Future<void> _deleteDocsInChunks(List<DocumentReference> refs) async {
    const int chunkSize = 400; // en dessous de la limite de 500 writes/batch
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