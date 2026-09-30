import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:adfoot/config/app_environment.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/services/callable_auth_guard.dart';

class FollowMutationResult {
  const FollowMutationResult({
    required this.success,
    this.following,
    this.followers,
    this.followings,
  });

  final bool success;
  final bool? following;
  final int? followers;
  final int? followings;

  factory FollowMutationResult.fromActionResponse(ActionResponse response) {
    final data = response.data ?? const <String, dynamic>{};

    return FollowMutationResult(
      success: response.success,
      following: data['following'] as bool?,
      followers: (data['followers'] as num?)?.toInt(),
      followings: (data['followings'] as num?)?.toInt(),
    );
  }
}

class FollowListPage {
  const FollowListPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final bool hasMore;
}

class FollowRepository {
  FollowRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
    : _injectedFirestore = firestore,
      _injectedFunctions = functions;

  // Résolus à l'usage. `FirebaseFirestore.instance` et
  // `FirebaseFunctions.instanceFor` lèvent tant qu'aucune app Firebase n'est
  // démarrée, si bien que construire ce repository — donc FollowController,
  // donc tout ce qui en dépend — exigeait un runtime Firebase complet, y
  // compris dans un test qui n'allait jamais suivre personne.
  final FirebaseFirestore? _injectedFirestore;
  final FirebaseFunctions? _injectedFunctions;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;
  FirebaseFunctions get _functions =>
      _injectedFunctions ??
      FirebaseFunctions.instanceFor(
        region: AppEnvironmentConfig.functionsRegion,
      );

  Future<FollowMutationResult> followUser(String targetUserId) {
    return _runFollowMutationWithRetry('followUser', targetUserId);
  }

  Future<FollowMutationResult> unfollowUser(String targetUserId) {
    return _runFollowMutationWithRetry('unfollowUser', targetUserId);
  }

  Stream<Set<String>> watchFollowingIds(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('following')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  Future<FollowListPage> fetchFollowList({
    required String uid,
    required String listType,
    String? cursor,
  }) async {
    final callable = _functions.httpsCallable(
      'listUserFollows',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    final raw =
        await CallableAuthGuard.callDataWithHttpFallback<Map<String, dynamic>>(
          callable,
          'listUserFollows',
          {
            'uid': uid,
            'listType': listType,
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          },
        );
    final response = ActionResponse.fromMap(
      raw,
      toastOverride: ToastLevel.none,
    );
    final data = response.data ?? const <String, dynamic>{};
    final rawItems = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return FollowListPage(
      items: rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
      nextCursor: data['nextCursor'] as String?,
      hasMore: data['hasMore'] == true,
    );
  }

  Future<FollowMutationResult> _runFollowMutation(
    String callableName,
    String targetUserId,
  ) async {
    final callable = _functions.httpsCallable(
      callableName,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );

    final raw =
        await CallableAuthGuard.callDataWithHttpFallback<Map<String, dynamic>>(
          callable,
          callableName,
          {'targetUserId': targetUserId},
        );

    final response = ActionResponse.fromMap(
      raw,
      toastOverride: ToastLevel.none,
    );

    return FollowMutationResult.fromActionResponse(response);
  }

  Future<FollowMutationResult> _runFollowMutationWithRetry(
    String callableName,
    String targetUserId,
  ) async {
    const maxAttempts = 2;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _runFollowMutation(callableName, targetUserId);
      } catch (error) {
        if (attempt >= maxAttempts || !_isTransientMutationError(error)) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    throw StateError('Follow mutation retry loop exited unexpectedly.');
  }

  static bool _isTransientMutationError(Object error) {
    if (error is FirebaseFunctionsException) {
      return _isTransientCode(error.code);
    }
    if (error is FirebaseException) {
      return _isTransientCode(error.code);
    }
    return false;
  }

  static bool _isTransientCode(String code) {
    switch (code) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'aborted':
      case 'cancelled':
      case 'resource-exhausted':
      case 'internal':
      case 'unknown':
        return true;
      default:
        return false;
    }
  }

  static bool isPermissionDenied(Object error) {
    return (error is FirebaseException && error.code == 'permission-denied') ||
        (error is FirebaseFunctionsException &&
            (error.code == 'permission-denied' ||
                error.code == 'unauthenticated'));
  }
}
