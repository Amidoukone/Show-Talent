import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class UploadVideoProcessingState {
  const UploadVideoProcessingState({
    required this.status,
    required this.optimized,
  });

  final String? status;
  final bool optimized;

  static UploadVideoProcessingState fromData(Map<String, dynamic>? data) {
    return UploadVideoProcessingState(
      status: data?['status']?.toString(),
      optimized: data?['optimized'] == true,
    );
  }
}

class UploadVideoRepository {
  UploadVideoRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _injectedFirestore = firestore,
      _injectedStorage = storage;

  // Resolved on use, not in the constructor. `FirebaseFirestore.instance` and
  // `FirebaseStorage.instance` both throw outright when no Firebase app
  // exists, which made the whole repository unconstructible anywhere Firebase
  // is not booted -- including a test that only ever wanted to count
  // documents in a fake.
  final FirebaseFirestore? _injectedFirestore;
  final FirebaseStorage? _injectedStorage;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _injectedStorage ?? FirebaseStorage.instance;
  static const Duration processingReadTimeout = Duration(seconds: 12);
  // Must outlive UploadVideoController._optimizationOverallTimeout (120s).
  // This is an inactivity timeout on the snapshot stream, so if it fires
  // first the controller loses its live signal and silently degrades to the
  // 10s polling fallback for the rest of the wait.
  static const Duration processingWatchTimeout = Duration(seconds: 150);

  DocumentReference<Map<String, dynamic>> _videoDoc(String videoId) {
    return _firestore.collection('videos').doc(videoId);
  }

  Future<UploadVideoProcessingState> fetchProcessingState(
    String videoId,
  ) async {
    final doc = await _videoDoc(videoId).get().timeout(processingReadTimeout);
    return UploadVideoProcessingState.fromData(doc.data());
  }

  Stream<UploadVideoProcessingState> watchProcessingState(String videoId) {
    return _videoDoc(videoId)
        .snapshots()
        .timeout(
          processingWatchTimeout,
          onTimeout: (sink) {
            sink.addError(
              TimeoutException('Video processing watch timed out.'),
            );
          },
        )
        .map((doc) => UploadVideoProcessingState.fromData(doc.data()));
  }

  /// Combien de vidéos publiées ce compte détient déjà.
  ///
  /// Une agrégation `count()`, pas une lecture de documents : le coût est
  /// celui d'une poignée de documents lus, quel que soit le nombre réel, et
  /// aucune donnée vidéo ne traverse le réseau.
  ///
  /// `status == 'ready'` est le miroir fidèle de `isPublicPlayerVideo()`
  /// (functions/src/upload_session.ts) pour un compte joueur : une vidéo
  /// masquée ou retirée par la modération voit `adminSetVideoStatus` écrire
  /// `hidden`/`removed` dans `status` lui-même, elle sort donc du compte des
  /// deux côtés.
  ///
  /// Les règles Firestore acceptent cette requête telle quelle : le filtre
  /// `uid == <appelant>` satisfait la troisième branche de `canReadVideo()`.
  Future<int> countPublishedVideos(String uid) async {
    final snapshot = await _firestore
        .collection('videos')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'ready')
        .count()
        .get()
        .timeout(processingReadTimeout);

    return snapshot.count ?? 0;
  }

  Future<void> deletePartialUpload(String videoPath, String thumbPath) {
    final videoRef = _storage.ref(videoPath);
    final thumbRef = _storage.ref(thumbPath);
    return Future.wait([
      videoRef.delete().catchError((_) {}),
      thumbRef.delete().catchError((_) {}),
    ]);
  }
}
