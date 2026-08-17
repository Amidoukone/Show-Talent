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
  UploadVideoRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
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

  Future<void> deletePartialUpload(String videoPath, String thumbPath) {
    final videoRef = _storage.ref(videoPath);
    final thumbRef = _storage.ref(thumbPath);
    return Future.wait([
      videoRef.delete().catchError((_) {}),
      thumbRef.delete().catchError((_) {}),
    ]);
  }
}
