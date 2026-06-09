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
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  DocumentReference<Map<String, dynamic>> _videoDoc(String videoId) {
    return _firestore.collection('videos').doc(videoId);
  }

  Future<UploadVideoProcessingState> fetchProcessingState(
    String videoId,
  ) async {
    final doc = await _videoDoc(videoId).get();
    return UploadVideoProcessingState.fromData(doc.data());
  }

  Stream<UploadVideoProcessingState> watchProcessingState(String videoId) {
    return _videoDoc(videoId).snapshots().map(
          (doc) => UploadVideoProcessingState.fromData(doc.data()),
        );
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
