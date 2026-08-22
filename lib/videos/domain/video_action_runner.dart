import 'package:flutter/foundation.dart';

import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/screens/success_toast.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

/// The user-facing actions a video carries.
enum VideoAction { like, share, report, delete, follow, addVideo }

/// The single implementation of what happens when a video action is tapped.
///
/// There used to be six, one per action, each re-deciding the same six
/// questions: is one already running, what do we show before the server
/// answers, what do we call, what does the answer mean, what do we do when it
/// fails, and what gets logged. They diverged, as six copies of anything do:
/// the like had a queue for rapid taps that nothing else had, the report had
/// no optimistic state at all, `isLikeLoading` was hard-coded to `false` in
/// the rail, and the rollback existed only for the like. Adding a seventh
/// action meant copying eighty lines and forgetting one of the six.
///
/// Everything that is *not* cross-cutting stays with the widget: confirmation
/// sheets, the platform share sheet, navigation. Those need a `BuildContext`;
/// this deliberately does not, which is what makes every action testable
/// without pumping a widget.
class VideoActionRunner extends ChangeNotifier {
  VideoActionRunner({
    required this.videoController,
    required this.followController,
  });

  final VideoController videoController;
  final FollowController followController;

  final Set<VideoAction> _inFlight = <VideoAction>{};

  /// Latest like target while a request is already in flight.
  ///
  /// A double tap on the heart must not queue two requests, and must not be
  /// swallowed either: the second tap becomes the target the loop retries
  /// once the first request lands.
  bool? _queuedLikeTarget;

  /// How many round trips the like may spend chasing a target that keeps
  /// changing under it.
  ///
  /// The reconciliation loop was unbounded, and it issues one `likeVideo`
  /// callable per turn. Its exit condition is "the server's answer matches
  /// the target the user last asked for", which holds only as long as the
  /// server *toggles*: give it any path that answers with a stable value the
  /// target disagrees with — a Firestore fallback that sets rather than
  /// flips, a moderation rule refusing the like while still reporting
  /// success — and it spins forever, one Cloud Function invocation per turn,
  /// for as long as the widget is alive.
  ///
  /// That is the same shape as the playback retry loop this app already had
  /// to bound (`_maxAutomaticRecoveries` in SmartVideoPlayer), and it was
  /// invisible for the same reason: nothing fails, so nothing is logged.
  ///
  /// Past this many attempts, the server's answer is the answer. Three covers
  /// a genuinely fast double tap; nothing sensible needs a fourth.
  static const int _maxLikeReconciliations = 3;

  bool _isDisposed = false;

  bool isRunning(VideoAction action) => _inFlight.contains(action);

  /// True while any action is running, for callers that only need "busy".
  bool get isBusy => _inFlight.isNotEmpty;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _begin(VideoAction action) {
    if (!_inFlight.add(action)) return;
    _notify();
  }

  void _end(VideoAction action) {
    if (!_inFlight.remove(action)) return;
    _notify();
  }

  void _notify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  /// Runs [body] under this action's in-flight guard.
  ///
  /// Returns `null` when the action was refused because one was already
  /// running — callers use that to leave the UI exactly as it was.
  Future<T?> _guard<T>(VideoAction action, Future<T> Function() body) async {
    if (_inFlight.contains(action)) return null;
    _begin(action);
    try {
      return await body();
    } finally {
      _end(action);
    }
  }

  // ---------------------------------------------------------------------------
  // LIKE
  // ---------------------------------------------------------------------------

  /// Toggles the like, showing the new state before the server confirms it.
  ///
  /// The optimistic value is published as *pending*, which is what keeps it on
  /// screen: the live Firestore stream delivers a batch whenever any video
  /// document changes, and a settled value would be replaced by this video's
  /// pre-tap counters on the very next unrelated snapshot.
  Future<void> toggleLike({
    required Video video,
    required String userId,
  }) async {
    final target = !videoController.hydrate(video).likes.contains(userId);
    _queuedLikeTarget = target;
    _applyLike(video, userId, target, pending: true);

    if (_inFlight.contains(VideoAction.like)) {
      // A request is already in flight; it will pick the new target up.
      return;
    }

    _begin(VideoAction.like);
    var confirmed = !target;
    try {
      var attempts = 0;
      while (!_isDisposed && _queuedLikeTarget != null) {
        if (attempts >= _maxLikeReconciliations) {
          // Stop chasing and show what the server last said.
          _queuedLikeTarget = null;
          _applyLike(video, userId, confirmed, pending: false);
          return;
        }
        attempts++;

        final requested = _queuedLikeTarget!;
        final response = await videoController.likeVideo(video, userId);
        if (_isDisposed) return;

        if (!response.success) {
          _queuedLikeTarget = null;
          _applyLike(video, userId, confirmed, pending: false);
          return;
        }

        confirmed = _likedFrom(response, fallback: requested);
        final latest = _queuedLikeTarget;
        if (latest == null || latest == confirmed) {
          _queuedLikeTarget = null;
          _applyLike(video, userId, confirmed, pending: false);
          return;
        }

        _applyLike(video, userId, latest, pending: true);
      }
    } finally {
      _end(VideoAction.like);
    }
  }

  void _applyLike(
    Video video,
    String userId,
    bool liked, {
    required bool pending,
  }) {
    videoController.applyLocalVideoState(
      video,
      (current) => current.withLike(userId, liked: liked),
      pending: pending,
    );
    _notify();
  }

  static bool _likedFrom(ActionResponse response, {required bool fallback}) {
    final raw = response.data?['liked'];
    return raw is bool ? raw : fallback;
  }

  // ---------------------------------------------------------------------------
  // REPORT / SHARE / DELETE
  // ---------------------------------------------------------------------------

  /// Records a report. `VideoController` publishes the resulting state and
  /// shows the toast, including the "already reported" case.
  Future<ActionResponse?> report({
    required Video video,
    required String userId,
  }) {
    return _guard(
      VideoAction.report,
      () => videoController.signalerVideo(video, userId),
    );
  }

  /// Records a share that actually happened.
  ///
  /// Called only after the platform sheet reports success — a dismissed share
  /// is not a share, and counting it was how the number drifted upward on
  /// nothing.
  Future<ActionResponse?> recordShare({required Video video}) {
    return _guard(
      VideoAction.share,
      () => videoController.partagerVideo(video),
    );
  }

  Future<ActionResponse?> delete({required Video video}) {
    return _guard(
      VideoAction.delete,
      () => videoController.deleteVideo(video),
    );
  }

  // ---------------------------------------------------------------------------
  // FOLLOW
  // ---------------------------------------------------------------------------

  /// Follows the publisher of [video].
  ///
  /// Refuses silently when there is nothing to do — the viewer is the author,
  /// or already follows them — because both are states the rail should not
  /// have offered in the first place, and a toast for them would be noise.
  Future<bool> followPublisher({
    required Video video,
    required String currentUserId,
    required bool isAlreadyFollowing,
  }) async {
    if (currentUserId.isEmpty ||
        video.uid == currentUserId ||
        isAlreadyFollowing) {
      return false;
    }

    final success = await _guard(
      VideoAction.follow,
      () => followController.followUser(currentUserId, video.uid),
    );

    if (success == null) return false;
    if (!success && !_isDisposed) {
      showErrorToast(VideoUiStrings.followUnavailable);
    }
    return success;
  }

  // ---------------------------------------------------------------------------
  // ADD VIDEO
  // ---------------------------------------------------------------------------

  /// Marks the upload flow as running for as long as [body] takes.
  ///
  /// The navigation and the refresh belong to the widget; only the in-flight
  /// flag the rail reads belongs here.
  Future<T?> runAddVideo<T>(Future<T> Function() body) =>
      _guard(VideoAction.addVideo, body);
}
