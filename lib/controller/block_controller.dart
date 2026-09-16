import 'dart:async';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/users/block_repository.dart';
import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:adfoot/services/app_logger.dart';

/// Keeps a reactive, unioned view of every uid the current user is blocked
/// with -- in either direction -- so profile/search/chat can each check
/// [isBlocked] without holding their own Firestore subscription.
///
/// Rebinds across sign-in/sign-out the same way ChatController does
/// (idTokenChanges + an epoch guard against a stale listener winning a race
/// after a rebind) -- that pattern exists because an earlier, simpler
/// version of ChatController's own auth listener silently stopped
/// reacting to sign-in/out once, so any new per-uid subscription copies it
/// rather than reinventing something less battle-tested.
class BlockController extends GetxController {
  BlockController({
    BlockRepository? blockRepository,
    AuthSessionService? authSessionService,
    this._currentUidResolver,
  }) : _blockRepository = blockRepository ?? BlockRepository(),
       _authSessionService = authSessionService ?? AuthSessionService();

  final BlockRepository _blockRepository;
  final AuthSessionService _authSessionService;
  final String? Function()? _currentUidResolver;

  final RxSet<String> blockedPairUids = <String>{}.obs;
  Set<String> _blockedByMe = <String>{};
  Set<String> _blockingMe = <String>{};

  StreamSubscription<User?>? _authSub;
  StreamSubscription<Set<String>>? _blockedByMeSub;
  StreamSubscription<Set<String>>? _blockingMeSub;

  int _bindEpoch = 0;
  String? _boundUid;

  bool isBlocked(String uid) => blockedPairUids.contains(uid);

  /// True only when *I* am the one who blocked [uid] -- the only direction
  /// I can undo. If [uid] blocked me instead, [isBlocked] is still true
  /// (used to hide their profile/messages from me), but there is nothing
  /// for a "Débloquer" menu item to do about it.
  bool isBlockedByMe(String uid) => _blockedByMe.contains(uid);

  String? _resolvedCurrentUid() {
    final injected = _currentUidResolver?.call()?.trim();
    if (injected != null && injected.isNotEmpty) {
      return injected;
    }

    if (Get.isRegistered<AuthController>()) {
      final currentUid = Get.find<AuthController>().currentUid?.trim();
      if (currentUid != null && currentUid.isNotEmpty) {
        return currentUid;
      }
    }

    return _authSessionService.currentUser?.uid;
  }

  Future<void> _handleProtectedAccessDenied() async {
    if (!Get.isRegistered<UserController>()) {
      return;
    }
    await Get.find<UserController>().handleProtectedAccessDenied(
      fallbackTitle: VideoUiStrings.protectedAccessTitle,
      fallbackMessage: VideoUiStrings.protectedAccessMessage,
    );
  }

  bool _isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  @override
  void onInit() {
    super.onInit();

    _authSub = _authSessionService.idTokenChanges().listen(
      (user) {
        if (user == null) {
          _resetLocalState();
          _unbind();
          _boundUid = null;
          return;
        }
        _bindFor(user.uid);
      },
      onError: (Object error) => AppLogger.warning(
        'auth state stream failed; block list has stopped following the session',
        source: 'BlockController._authSub',
        error: error,
      ),
    );

    final uid = _resolvedCurrentUid();
    if (uid != null) {
      _bindFor(uid);
    }
  }

  @override
  void onClose() {
    _authSub?.cancel();
    _unbind();
    super.onClose();
  }

  void _resetLocalState() {
    _blockedByMe = <String>{};
    _blockingMe = <String>{};
    blockedPairUids.clear();
  }

  void _recomputeUnion() {
    blockedPairUids.assignAll({..._blockedByMe, ..._blockingMe});
  }

  void _bindFor(String uid) {
    if (_boundUid == uid && _blockedByMeSub != null) {
      return;
    }

    _boundUid = uid;
    _unbind();

    final myEpoch = ++_bindEpoch;

    _blockedByMeSub = _blockRepository
        .watchBlockedByMe(uid)
        .listen(
          (ids) {
            if (myEpoch != _bindEpoch) return;
            _blockedByMe = ids;
            _recomputeUnion();
          },
          onError: (Object error) {
            AppLogger.warning(
              'watchBlockedByMe failed: $error',
              source: 'BlockController._bindFor',
              error: error,
            );
            if (_isPermissionDenied(error)) {
              unawaited(_handleProtectedAccessDenied());
            }
          },
        );

    _blockingMeSub = _blockRepository
        .watchBlockingMe(uid)
        .listen(
          (ids) {
            if (myEpoch != _bindEpoch) return;
            _blockingMe = ids;
            _recomputeUnion();
          },
          onError: (Object error) {
            AppLogger.warning(
              'watchBlockingMe failed: $error',
              source: 'BlockController._bindFor',
              error: error,
            );
            if (_isPermissionDenied(error)) {
              unawaited(_handleProtectedAccessDenied());
            }
          },
        );
  }

  void _unbind() {
    _blockedByMeSub?.cancel();
    _blockedByMeSub = null;
    _blockingMeSub?.cancel();
    _blockingMeSub = null;
  }

  Future<bool> blockUser(String targetUid) async {
    final currentUid = _resolvedCurrentUid();
    if (currentUid == null || currentUid == targetUid) return false;

    _blockedByMe = {..._blockedByMe, targetUid};
    _recomputeUnion();

    try {
      await _blockRepository.blockUser(
        blockerUid: currentUid,
        blockedUid: targetUid,
      );
      return true;
    } catch (error, st) {
      AppLogger.warning(
        'blockUser error: $error',
        source: 'BlockController.blockUser',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
      _blockedByMe = {..._blockedByMe}..remove(targetUid);
      _recomputeUnion();
      return false;
    }
  }

  Future<bool> unblockUser(String targetUid) async {
    final currentUid = _resolvedCurrentUid();
    if (currentUid == null) return false;

    final wasBlocked = _blockedByMe.contains(targetUid);
    _blockedByMe = {..._blockedByMe}..remove(targetUid);
    _recomputeUnion();

    try {
      await _blockRepository.unblockUser(
        blockerUid: currentUid,
        blockedUid: targetUid,
      );
      return true;
    } catch (error, st) {
      AppLogger.warning(
        'unblockUser error: $error',
        source: 'BlockController.unblockUser',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
      if (wasBlocked) {
        _blockedByMe = {..._blockedByMe, targetUid};
        _recomputeUnion();
      }
      return false;
    }
  }
}
