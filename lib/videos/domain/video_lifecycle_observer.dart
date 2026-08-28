import 'dart:async';

import 'package:flutter/widgets.dart';

import '../video_manager.dart';

/// Tells [VideoManager] when the app leaves and returns to the foreground.
///
/// Registered once for the process, from `AppBindings`, rather than by a
/// screen. That is the whole point: the widgets in the playback path already
/// observe the lifecycle correctly and pause what they are holding, but they
/// only exist while the feed is on screen, and they only know about their own
/// controller. What kept playing after the app was backgrounded was never the
/// widget's controller — it was an initialisation still in flight inside the
/// manager, which completed a moment later and called `play()` on a video with
/// no screen to show it.
///
/// So the manager needs the signal directly, and it needs it for the whole
/// process: a preload finishing, an automatic recovery re-attaching, a
/// download completing. None of those has a widget watching.
///
/// Deliberately not a `WidgetsBindingObserver` on `VideoManager` itself. The
/// manager is a singleton constructed by `AppBindings`, and touching
/// `WidgetsBinding.instance` from its constructor would make every test that
/// builds one depend on a live binding. Keeping the binding here leaves the
/// manager a plain object that can be driven directly with `setAppResumed`.
class VideoLifecycleObserver with WidgetsBindingObserver {
  VideoLifecycleObserver({VideoManager? videoManager})
    : _videoManager = videoManager ?? VideoManager();

  final VideoManager _videoManager;
  bool _registered = false;

  void start() {
    if (_registered) return;
    _registered = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    if (!_registered) return;
    _registered = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `resumed` is the only state in which a video may play. Everything else —
    // `inactive` on the way out, `hidden` between them, `paused` in the
    // background, `detached` on the way down — means there is no surface to
    // play to.
    //
    // Written as "not resumed" rather than as a list on purpose: `hidden` was
    // added to this enum after this app was written, and a list would have
    // silently let a whole state through.
    unawaited(
      _videoManager.setAppResumed(state == AppLifecycleState.resumed),
    );
  }
}
