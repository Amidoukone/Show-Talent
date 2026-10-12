import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

/// The installed build, read once per process and shared by everyone who
/// needs to name it.
///
/// Three places ask the same question for three reasons, and each used to
/// answer it on its own: the version label at the bottom of Outils (so a
/// tester can say which build they are on), the push-token document (so
/// `user_push_tokens` says which build registered), and `client_logs` (so a
/// production error can be attributed to a build at all).
///
/// The last one is why this class exists. `client_logs` carried no version,
/// and the iOS notification outage was diagnosed across four builds partly by
/// reasoning "the error stopped appearing, therefore the new build must be
/// installed" — an inference where a field would have answered. A single
/// cached read makes attaching it free everywhere.
///
/// Read from the platform package manifest, never from a compile-time
/// constant: the question is "which artifact is on this phone", and only the
/// installed package knows. A `--dart-define` would report what the *source*
/// believed at build time, which is the very thing that cannot be trusted
/// when a tester is unsure what they installed.
class AppVersion {
  AppVersion._();

  static String? _versionName;
  static String? _buildNumber;
  static Future<void>? _inFlight;

  /// The version name and build number joined by `+`, or `null` until the
  /// platform channel has answered.
  ///
  /// No example literal here on purpose: `app_version_label_test` refuses a
  /// version string anywhere in this file or the label's, because one written
  /// down beside the reader drifts from the artifact at the next build — the
  /// exact confusion both exist to remove.
  ///
  /// Synchronous on purpose: the callers that matter — a log entry being
  /// enqueued, a token being saved — are on paths that must not wait on a
  /// platform channel. [warm] runs during bootstrap, so by the time either
  /// fires the answer is already here; if it is not, the record simply goes
  /// without it rather than holding anything up.
  static String? get cached {
    final version = _versionName;
    if (version == null || version.isEmpty) {
      return null;
    }
    final build = _buildNumber;
    return build == null || build.isEmpty ? version : '$version+$build';
  }

  /// The version name alone, once known.
  static String? get versionName => _versionName;

  /// The build number alone: the half that tells two builds of one release
  /// apart, and the only half that changes between them.
  static String? get buildNumber => _buildNumber;

  /// Starts the one-off read without waiting for it.
  static void warm() => unawaited(resolve());

  /// Reads the installed build once, if nobody has yet.
  ///
  /// Concurrent callers share one read: the version label and [warm] race on
  /// a cold start, and `PackageInfo.fromPlatform` is a platform channel round
  /// trip worth making exactly once.
  static Future<void> resolve() {
    if (_versionName != null) {
      return Future<void>.value();
    }
    return _inFlight ??= _read();
  }

  static Future<void> _read() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isEmpty) {
        return;
      }
      _versionName = version;
      _buildNumber = info.buildNumber.trim();
    } catch (_) {
      // Diagnostic only: a device that cannot name its own build still
      // registers for notifications, still logs, and still works. The next
      // call tries again.
    } finally {
      _inFlight = null;
    }
  }

  /// Clears the cache so a test can supply its own package values.
  static void resetForTests() {
    _versionName = null;
    _buildNumber = null;
    _inFlight = null;
  }
}
