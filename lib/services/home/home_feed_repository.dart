import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_search_matcher.dart';

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

  Future<List<AppUser>> searchPlayers(String rawQuery, {int limit = 60}) async {
    final normalized = normalizeVideoSearchText(rawQuery);
    if (normalized.isEmpty || limit <= 0) return const <AppUser>[];
    final tokens = expandVideoSearchQuery(rawQuery)
        .where((term) => !term.contains(' ') && term.length <= 24)
        .take(30)
        .toList(growable: false);
    if (tokens.isEmpty) return const <AppUser>[];
    final results = <AppUser>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    final query = _firestore
        .collection('public_profiles')
        .where('isSearchable', isEqualTo: true)
        .where('isMinorProfile', isEqualTo: false)
        .where('searchPrefixes', arrayContainsAny: tokens);
    while (results.length < limit) {
      final page =
          await (cursor == null
                  ? query.limit(100)
                  : query.startAfterDocument(cursor).limit(100))
              .get();
      for (final doc in page.docs) {
        final user = AppUser.fromMap({...doc.data(), 'uid': doc.id});
        if (matchesUserVideoSearch(user, rawQuery)) results.add(user);
        if (results.length >= limit) break;
      }
      if (page.docs.length < 100) break;
      cursor = page.docs.last;
    }
    return results;
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
        .where('publicFeedVisible', isEqualTo: true)
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
        .where('publicFeedVisible', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map(Video.fromDoc)
        .where((video) => video.effectiveUrl.isNotEmpty)
        .toList(growable: false);
  }
}
