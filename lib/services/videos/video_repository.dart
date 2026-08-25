import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:firebase_auth/firebase_auth.dart';

import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/services/videos/video_action_service.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

class VideoFeedCursor {
  const VideoFeedCursor._(this.snapshot);

  final DocumentSnapshot<Map<String, dynamic>> snapshot;
}

class VideoFeedPage {
  const VideoFeedPage({
    required this.videos,
    required this.cursor,
    required this.fetchedCount,
  });

  final List<Video> videos;
  final VideoFeedCursor? cursor;
  final int fetchedCount;
}

class VideoLiveBatch {
  const VideoLiveBatch({required this.videos, required this.cursor});

  final List<Video> videos;
  final VideoFeedCursor? cursor;
}

class VideoRepository {
  VideoRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _injectedFirestore = firestore,
      _injectedAuth = auth;

  // Résolus à l'usage, pas à la construction. `FirebaseFirestore.instance`
  // lève dès qu'aucune app Firebase n'est démarrée, ce qui rendait ce
  // repository — et donc `VideoController`, et donc tout le registre de
  // contextes vidéo — impossible à instancier hors d'un runtime complet.
  // Un repository qui ne peut pas exister sans son backend n'est testable par
  // personne.
  final FirebaseFirestore? _injectedFirestore;
  final FirebaseAuth? _injectedAuth;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _videosCollection =>
      _firestore.collection('videos');

  /// The field the public feed is ordered by, and the one it falls back to.
  ///
  ///
  /// `approvedAt`, not `updatedAt`: they hold the same instant on every one
  /// of adfoot-production's fourteen ready documents today, but they answer
  /// different questions. `updatedAt` moves on *any* admin write —
  /// `adminSetVideoStatus` stamps it on hide, on re-approve, on every
  /// moderation pass (functions/src/admin_content_actions.ts) — so a video
  /// hidden and put back six months later would re-enter at the top of the
  /// feed and be announced as new. `approvedAt` is the moment it became
  /// public, written once by the same transaction that sets `status: ready`,
  /// which is the only path to that status. Every ready video therefore has
  /// it, and no ready video can be missing from the ordering.
  /// Ordering by it needs a composite index (`status` ASC, `approvedAt` DESC)
  /// that has to exist in the project before a build that uses it reaches a
  /// phone. It does not exist yet in adfoot-production, and a Firestore index
  /// is not instant even once deployed — it builds, and the query fails
  /// `failed-precondition` until it is ready.
  ///
  /// So the release and the index are deliberately decoupled: the first
  /// query that finds no index downgrades the whole app to [_legacyOrderField]
  /// for the rest of the process, and the feed keeps working exactly as it
  /// does today. Without this the two would have to ship in the right order,
  /// and getting it wrong means an empty home screen for everyone.
  static const String _feedOrderField = 'approvedAt';
  static const String _legacyOrderField = 'updatedAt';

  /// Process-wide, because the answer is a property of the project, not of a
  /// repository instance: every surface asks the same Firestore the same
  /// question, and one of them finding out is enough.
  static String _activeOrderField = _feedOrderField;

  @visibleForTesting
  static String get activeOrderField => _activeOrderField;

  @visibleForTesting
  static void resetOrderFieldForTests() {
    _activeOrderField = _feedOrderField;
  }

  /// True when Firestore refused a query for want of an index.
  static bool _isMissingIndex(Object error) {
    if (error is! FirebaseException) return false;
    if (error.code == 'failed-precondition') return true;
    // The Android SDK reports this one as `unknown` with the index message in
    // the body often enough to be worth matching on.
    return (error.message ?? '').toLowerCase().contains('requires an index');
  }

  void _downgradeOrderField() {
    if (_activeOrderField == _legacyOrderField) return;
    _activeOrderField = _legacyOrderField;
  }

  Query<Map<String, dynamic>> _readyVideosQuery({
    required int limit,
    required String orderField,
  }) {
    return _videosCollection
        .where('status', isEqualTo: 'ready')
        .orderBy(orderField, descending: true)
        .limit(limit);
  }

  static VideoLiveBatch _toLiveBatch(QuerySnapshot<Map<String, dynamic>> snap) {
    return VideoLiveBatch(
      videos: _playableVideos(snap.docs),
      cursor: snap.docs.isEmpty ? null : VideoFeedCursor._(snap.docs.last),
    );
  }

  Stream<VideoLiveBatch> watchReadyVideos({required int limit}) {
    late final StreamController<VideoLiveBatch> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;

    void subscribe(String orderField) {
      unawaited(subscription?.cancel());
      subscription = _readyVideosQuery(limit: limit, orderField: orderField)
          .snapshots()
          .listen(
            (snapshot) => controller.add(_toLiveBatch(snapshot)),
            onError: (Object error, StackTrace stackTrace) {
              if (orderField != _legacyOrderField && _isMissingIndex(error)) {
                _downgradeOrderField();
                subscribe(_legacyOrderField);
                return;
              }
              controller.addError(error, stackTrace);
            },
          );
    }

    controller = StreamController<VideoLiveBatch>(
      onListen: () => subscribe(_activeOrderField),
      onCancel: () async {
        await subscription?.cancel();
        subscription = null;
      },
    );

    return controller.stream;
  }

  Future<VideoFeedPage> fetchReadyVideosPage({
    required int limit,
    VideoFeedCursor? startAfter,
  }) async {
    try {
      return await _fetchReadyVideosPage(
        limit: limit,
        startAfter: startAfter,
        orderField: _activeOrderField,
      );
    } catch (error) {
      if (_activeOrderField == _legacyOrderField || !_isMissingIndex(error)) {
        rethrow;
      }
      _downgradeOrderField();
      return _fetchReadyVideosPage(
        limit: limit,
        startAfter: startAfter,
        orderField: _legacyOrderField,
      );
    }
  }

  Future<VideoFeedPage> _fetchReadyVideosPage({
    required int limit,
    required VideoFeedCursor? startAfter,
    required String orderField,
  }) async {
    Query<Map<String, dynamic>> query = _readyVideosQuery(
      limit: limit,
      orderField: orderField,
    );

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter.snapshot);
    }

    final snapshot = await query.get();
    return VideoFeedPage(
      videos: _playableVideos(snapshot.docs),
      cursor: snapshot.docs.isEmpty
          ? startAfter
          : VideoFeedCursor._(snapshot.docs.last),
      fetchedCount: snapshot.docs.length,
    );
  }

  Future<ActionResponse> reportVideoWithFirestoreFallback(
    String videoId,
    String userId,
  ) async {
    final authUser = _auth.currentUser;
    if (authUser == null || authUser.uid != userId) {
      return VideoActionService.authRequiredResponse();
    }

    try {
      await authUser.getIdToken();

      final ref = _videosCollection.doc(videoId);
      return _firestore.runTransaction<ActionResponse>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          return ActionResponse.failure(
            message: VideoUiStrings.videoNotFound,
            code: 'not-found',
          );
        }

        final data = snap.data() ?? const <String, dynamic>{};
        final reports = _asStringList(data['reports']);
        final reportCount = _asInt(data['reportCount']) ?? reports.length;

        if (reports.contains(userId)) {
          return ActionResponse.failure(
            message: VideoUiStrings.videoAlreadyReported,
            code: 'already_reported',
            toast: ToastLevel.info,
          );
        }

        final nextReportCount = reportCount >= reports.length
            ? reportCount + 1
            : reports.length + 1;
        tx.update(ref, {
          'reports': FieldValue.arrayUnion([userId]),
          'reportCount': FieldValue.increment(1),
        });

        return ActionResponse(
          success: true,
          code: 'reported',
          message: VideoUiStrings.reportSent,
          data: {'reportCount': nextReportCount},
        );
      });
    } on FirebaseException catch (error) {
      if (VideoActionService.isAuthAccessFailure(error)) {
        return VideoActionService.authRequiredResponse();
      }

      if (isPermissionDenied(error)) {
        return VideoActionService.sessionRevokedResponse();
      }

      return ActionResponse.failure(
        message: VideoUiStrings.reportUnavailable,
        code: error.code,
        retriable: true,
      );
    } catch (_) {
      return ActionResponse.failure(
        message: VideoUiStrings.reportUnavailable,
        retriable: true,
      );
    }
  }

  Future<ActionResponse> likeVideoWithFirestoreFallback(
    String videoId,
    String userId,
  ) async {
    final authUser = _auth.currentUser;
    if (authUser == null || authUser.uid != userId) {
      return VideoActionService.authRequiredResponse();
    }

    try {
      await authUser.getIdToken(true);

      final ref = _videosCollection.doc(videoId);
      return _firestore.runTransaction<ActionResponse>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          return ActionResponse.failure(
            message: VideoUiStrings.videoNotFound,
            code: 'not-found',
          );
        }

        final data = snap.data() ?? const <String, dynamic>{};
        final likes = _asStringList(data['likes']);
        final hasLiked = likes.contains(userId);
        final liked = !hasLiked;

        tx.update(ref, {
          'likes': liked
              ? FieldValue.arrayUnion([userId])
              : FieldValue.arrayRemove([userId]),
        });

        return ActionResponse(
          success: true,
          code: 'like-toggled',
          message: liked
              ? VideoUiStrings.likeAdded
              : VideoUiStrings.likeRemoved,
          data: {
            'liked': liked,
            'likes': liked
                ? likes.length + 1
                : (likes.isNotEmpty ? likes.length - 1 : 0),
          },
        );
      });
    } on FirebaseException catch (error) {
      if (VideoActionService.isAuthAccessFailure(error)) {
        return VideoActionService.authRequiredResponse();
      }

      if (isPermissionDenied(error)) {
        return VideoActionService.sessionRevokedResponse();
      }

      return ActionResponse.failure(
        message: VideoUiStrings.likeUnavailable,
        code: error.code,
        retriable: true,
      );
    } catch (_) {
      return ActionResponse.failure(
        message: VideoUiStrings.likeUnavailable,
        retriable: true,
      );
    }
  }

  Future<ActionResponse> shareVideoWithFirestoreFallback(String videoId) async {
    final authUser = _auth.currentUser;
    if (authUser == null) {
      return VideoActionService.authRequiredResponse();
    }

    try {
      await authUser.getIdToken(true);

      final ref = _videosCollection.doc(videoId);
      return _firestore.runTransaction<ActionResponse>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          return ActionResponse.failure(
            message: VideoUiStrings.videoNotFound,
            code: 'not-found',
          );
        }

        final data = snap.data() ?? const <String, dynamic>{};
        final currentShareCount = _asInt(data['shareCount']) ?? 0;
        final nextShareCount = currentShareCount + 1;

        tx.update(ref, {'shareCount': FieldValue.increment(1)});

        return ActionResponse(
          success: true,
          code: 'shared',
          message: VideoUiStrings.shareRecorded,
          data: {'shareCount': nextShareCount},
        );
      });
    } on FirebaseException catch (error) {
      if (VideoActionService.isAuthAccessFailure(error)) {
        return VideoActionService.authRequiredResponse();
      }

      if (isPermissionDenied(error)) {
        return VideoActionService.sessionRevokedResponse();
      }

      return ActionResponse.failure(
        message: VideoUiStrings.shareUnavailable,
        code: error.code,
        retriable: true,
      );
    } catch (_) {
      return ActionResponse.failure(
        message: VideoUiStrings.shareUnavailable,
        retriable: true,
      );
    }
  }

  static bool isPermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  static List<Video> _playableVideos(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .map(Video.fromDoc)
        .where((video) => video.effectiveUrl.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _asStringList(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }

    return raw.map((value) => value.toString()).toList(growable: false);
  }

  static int? _asInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return null;
  }
}
