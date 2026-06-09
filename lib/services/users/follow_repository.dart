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

class FollowRepository {
  FollowRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ??
            FirebaseFunctions.instanceFor(
              region: AppEnvironmentConfig.functionsRegion,
            );

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Future<FollowMutationResult> followUser(String targetUserId) {
    return _runFollowMutation('followUser', targetUserId);
  }

  Future<FollowMutationResult> unfollowUser(String targetUserId) {
    return _runFollowMutation('unfollowUser', targetUserId);
  }

  Future<List<Map<String, dynamic>>> fetchFollowList({
    required String uid,
    required String listType,
    required Set<String> currentFollowings,
  }) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return [];

    final data = doc.data() ?? const <String, dynamic>{};
    final rawIds = (listType == 'followers'
            ? data['followersList']
            : data['followingsList']) as List<dynamic>? ??
        const <dynamic>[];
    final ids = <String>[];
    final seen = <String>{};

    for (final value in rawIds) {
      final normalized = value.toString().trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      ids.add(normalized);
    }

    if (ids.isEmpty) return [];

    final resultById = <String, Map<String, dynamic>>{};
    const int batchSize = 10;

    for (int i = 0; i < ids.length; i += batchSize) {
      final chunk = ids.sublist(i, (i + batchSize).clamp(0, ids.length));

      final querySnapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        resultById[doc.id] = {
          'uid': doc.id,
          'nom': data['nom'] ?? '',
          'photoProfil': data['photoProfil'] ?? '',
          'role': data['role'] ?? 'Non specifie',
          'isFollowing': currentFollowings.contains(doc.id),
        };
      }
    }

    return ids
        .map((id) => resultById[id])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<FollowMutationResult> _runFollowMutation(
    String callableName,
    String targetUserId,
  ) async {
    final callable = _functions.httpsCallable(
      callableName,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
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

  static bool isPermissionDenied(Object error) {
    return (error is FirebaseException && error.code == 'permission-denied') ||
        (error is FirebaseFunctionsException &&
            (error.code == 'permission-denied' ||
                error.code == 'unauthenticated'));
  }
}
