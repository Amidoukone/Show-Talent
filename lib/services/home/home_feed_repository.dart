import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';

class HomeFeedRepository {
  const HomeFeedRepository({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  Future<Video?> fetchReadyVideoById(String videoId) async {
    final targetId = videoId.trim();
    if (targetId.isEmpty) {
      return null;
    }

    final doc = await _firestore.collection('videos').doc(targetId).get();
    if (!doc.exists) {
      return null;
    }

    final video = Video.fromDoc(doc);
    if (video.status != 'ready' || video.effectiveUrl.isEmpty) {
      return null;
    }
    return video;
  }

  Future<List<AppUser>> fetchSearchablePlayers({int limit = 300}) async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'joueur')
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) {
          final data = doc.data();
          return AppUser.fromMap({...data, 'uid': data['uid'] ?? doc.id});
        })
        .where((user) => user.uid.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<Video>> fetchReadyVideosForAuthors(
    List<String> authorIds, {
    required int limit,
  }) async {
    final ids = authorIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (ids.isEmpty) {
      return const <Video>[];
    }

    final snapshot = await _firestore
        .collection('videos')
        .where('status', isEqualTo: 'ready')
        .where('uid', whereIn: ids)
        .limit(limit)
        .get();

    return snapshot.docs
        .map(Video.fromDoc)
        .where((video) => video.effectiveUrl.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<Video>> fetchRecentReadyVideos({required int limit}) async {
    final snapshot = await _firestore
        .collection('videos')
        .where('status', isEqualTo: 'ready')
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map(Video.fromDoc)
        .where((video) => video.effectiveUrl.isNotEmpty)
        .toList(growable: false);
  }
}
