import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/auth/password_reset_flow.dart';
import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../config/app_routes.dart';
import '../config/app_environment.dart';
import '../utils/email_action_link_parser.dart';
import '../utils/video_share_links.dart';
import 'package:adfoot/services/app_logger.dart';

/// Handles Firebase email verification links and password reset links.
/// Mobile listens to incoming app links. Web is handled elsewhere.
class EmailLinkHandler {
  static final AuthSessionService _authSessionService = AuthSessionService();
  static AppLinks? _appLinks;
  static StreamSubscription<Uri?>? _sub;
  static bool _initialized = false;
  static bool _isInitializing = false;
  static final Set<String> _handledOobCodes = <String>{};
  static String? _lastVideoLinkKey;
  static DateTime? _lastVideoLinkAt;

  static StreamController<void>? _verifiedCtrl;
  static Stream<void> get onEmailVerified {
    _verifiedCtrl ??= StreamController<void>.broadcast();
    return _verifiedCtrl!.stream;
  }

  static void _emitVerified() {
    try {
      _verifiedCtrl?.add(null);
    } catch (_) {}
  }

  static Set<String> get _allowedHosts =>
      AppEnvironmentConfig.emailLinkAllowedHosts;

  static void _logDebug(String message) {
    if (kDebugMode) {
      AppLogger.debug(message);
    }
  }

  /// Records a failure that a user is standing in front of.
  ///
  /// [_logDebug] is gated twice — by `kDebugMode` here and again by
  /// `AppLogger._shouldSendToRemote`, which drops `debug` unconditionally. In
  /// a release build it therefore writes nowhere at all, which is why a reset
  /// link that stopped working left no trace anywhere: not on the screen, not
  /// in Crashlytics, not in the client log. `warning` is sampled in
  /// production but does reach the remote logger, so a broken link flow is
  /// now something that can be seen rather than guessed at.
  static void _logIssue(String message, {Object? error}) {
    AppLogger.warning(
      message,
      source: 'email_link_handler',
      error: error,
    );
  }

  static Future<void> init() async {
    if (kIsWeb || Get.testMode || _initialized || _isInitializing) {
      return;
    }
    _isInitializing = true;

    try {
      _appLinks ??= AppLinks();

      try {
        final initialUri = await _appLinks!
            .getInitialLink()
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (initialUri != null) {
          await _handle(initialUri);
        }
      } on PlatformException catch (e) {
        _logDebug('EmailLinkHandler.getInitialLink PlatformException: $e');
      } catch (e) {
        _logDebug('EmailLinkHandler.getInitialLink unexpected: $e');
      }

      await _sub?.cancel();
      _sub = _appLinks!.uriLinkStream.listen(
        (Uri? uri) {
          if (uri != null) {
            unawaited(_handle(uri));
          }
        },
        onError: (e) {
          _logDebug('EmailLinkHandler stream error: $e');
        },
        cancelOnError: false,
      );
      _initialized = true;
    } catch (e, stack) {
      _logDebug('EmailLinkHandler.init failed: $e\n$stack');
      _initialized = false;
    } finally {
      _isInitializing = false;
    }
  }

  static Future<bool> _handle(Uri link) async {
    final videoId = VideoShareLinks.extractVideoId(link);
    if (videoId != null) {
      return _handleVideoShareLink(videoId, link);
    }

    if (link.scheme != 'https' || !_allowedHosts.contains(link.host)) {
      _logDebug('EmailLinkHandler ignored link with unsupported host: $link');
      return false;
    }

    final params = EmailActionLinkParser.extract(link);
    final mode = params['mode'];
    final oob = params['oobCode'];

    if (mode == 'resetPassword' && oob != null && oob.isNotEmpty) {
      return _handlePasswordResetLink(oob);
    }

    if (mode != 'verifyEmail' || oob == null || oob.isEmpty) {
      _logDebug('EmailLinkHandler ignored unrelated link: $link');
      return false;
    }

    if (_handledOobCodes.contains(oob)) {
      _logDebug('EmailLinkHandler ignored duplicate verifyEmail oobCode.');
      return false;
    }
    _handledOobCodes.add(oob);

    try {
      await _authSessionService.applyEmailVerificationCode(oob);

      final user = _authSessionService.currentUser;
      if (user != null && user.emailVerified) {
        await _authSessionService.finalizeCurrentVerifiedSession(
          updateLastLogin: true,
          signOutOnInvalid: true,
        );
      }

      _emitVerified();
      _logDebug('EmailLinkHandler applied verifyEmail action successfully.');
      return true;
    } on FirebaseAuthException catch (e) {
      _logIssue('verifyEmail link refused (${e.code})', error: e);
      return false;
    } catch (e) {
      _logIssue('verifyEmail link failed unexpectedly', error: e);
      return false;
    }
  }

  /// Opens the in-app reset screen for a link the user just tapped.
  ///
  /// Three things changed here, all of them things the user could see:
  ///
  /// 1. The flow is claimed *before* `verifyPasswordResetCode` — that call
  ///    reaches the network, and on a cold start `SplashScreen` and
  ///    `UserController` are resolving the session in parallel and about to
  ///    replace the whole stack. See [PasswordResetFlow].
  /// 2. The screen is installed with `offAllNamed`, not pushed. A push landed
  ///    on top of the splash route, so the first `offAllNamed` from either of
  ///    those two owners took it away again, and back from the reset screen
  ///    led to a splash that immediately re-resolved the session.
  /// 3. A refused code no longer fails in silence. An expired or already-used
  ///    link used to return `false` here and nothing else: the app simply
  ///    opened on the login screen with no hint that the link was the reason.
  ///    It now lands on login *with* the explanation, through the notice
  ///    arguments that screen already reads.
  static Future<bool> _handlePasswordResetLink(String oob) async {
    _logDebug('EmailLinkHandler detected resetPassword link.');

    if (_handledOobCodes.contains(oob)) {
      _logDebug('EmailLinkHandler ignored duplicate resetPassword oobCode.');
      return false;
    }
    _handledOobCodes.add(oob);

    PasswordResetFlow.begin();
    try {
      // The address the code belongs to, so the screen can name the account
      // being changed instead of asking for a password in the abstract.
      final email = await FirebaseAuth.instance.verifyPasswordResetCode(oob);

      final opened = await _navigateWhenReady(
        () => Get.offAllNamed(
          AppRoutes.resetPassword,
          arguments: <String, dynamic>{
            'oobCode': oob,
            if (email.trim().isNotEmpty) 'email': email.trim(),
          },
        ),
      );

      if (!opened) {
        // No screen was installed, so nothing will ever release the flow —
        // and an armed flow mutes session routing. Releasing it here is what
        // keeps a failed hand-off from stranding the app on the splash
        // screen, which would be a worse bug than the one being fixed.
        PasswordResetFlow.end();
        _handledOobCodes.remove(oob);
        return false;
      }

      return true;
    } on FirebaseAuthException catch (e) {
      PasswordResetFlow.end();
      // A refusal that came from the network rather than from the code itself
      // must not burn the link for a second tap.
      _handledOobCodes.remove(oob);
      _logIssue(
        'resetPassword link refused (${e.code})',
        error: e,
      );
      await _openLoginWithNotice(
        title: 'Lien de réinitialisation refusé',
        message: AuthErrorMapper.toMessage(e),
      );
      return false;
    } catch (e) {
      PasswordResetFlow.end();
      _handledOobCodes.remove(oob);
      _logIssue('resetPassword link failed unexpectedly', error: e);
      await _openLoginWithNotice(
        title: 'Lien de réinitialisation refusé',
        message:
            'Impossible d’ouvrir ce lien de réinitialisation. '
            'Demandez-en un nouveau depuis la page de connexion.',
      );
      return false;
    }
  }

  static Future<bool> _openLoginWithNotice({
    required String title,
    required String message,
  }) {
    return _navigateWhenReady(
      () => Get.offAllNamed(
        AppRoutes.login,
        arguments: <String, dynamic>{
          'sessionNoticeTitle': title,
          'sessionNoticeMessage': message,
          'sessionNoticeKind': 'error',
        },
      ),
    );
  }

  /// Runs [navigate] as soon as there is a navigator to run it on.
  ///
  /// [init] is called from `AppBootstrap.initialize()`, which finishes before
  /// `runApp`, so on a cold start — the launch a tapped link produces —
  /// there is no `Get.key.currentState` yet. The previous code guessed 300 ms
  /// and navigated blind; on a cold device that was regularly too early, and
  /// the call was simply lost. Poll instead, briefly, and give up rather than
  /// navigate into nothing.
  static Future<bool> _navigateWhenReady(void Function() navigate) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (Get.key.currentState != null) {
        navigate();
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    _logIssue('gave up waiting for a navigator; link was dropped');
    return false;
  }

  static Future<bool> _handleVideoShareLink(String videoId, Uri link) async {
    final key = link.replace(queryParameters: null, fragment: null).toString();
    final now = DateTime.now();
    final lastAt = _lastVideoLinkAt;
    if (_lastVideoLinkKey == key &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 2)) {
      _logDebug('EmailLinkHandler ignored duplicate video share link: $link');
      return false;
    }

    _lastVideoLinkKey = key;
    _lastVideoLinkAt = now;

    final routeArguments = <String, dynamic>{
      'tab': 0,
      'refresh': true,
      'videoId': videoId,
      'autoplay': true,
      'source': 'video_share_link',
    };

    try {
      final snapshot = await _authSessionService.resolveSessionSafely(
        _authSessionService.currentUser,
        waitForVerifiedUserDocument: true,
        syncVerifiedUserRecord: false,
        signOutOnInvalid: true,
      );

      if (Get.isRegistered<UserController>()) {
        await Get.find<UserController>().applyResolvedSessionSnapshot(
          snapshot,
          routeArguments: routeArguments,
        );
      } else {
        Get.offAllNamed(
          snapshot.destination.routeName,
          arguments: routeArguments,
        );
      }

      return true;
    } catch (e, stack) {
      _logDebug('EmailLinkHandler video share route failed: $e\n$stack');
      _openMainWithVideoArguments(routeArguments);
      return true;
    }
  }

  static void _openMainWithVideoArguments(Map<String, dynamic> arguments) {
    // Same reasoning as the reset path: wait for a navigator rather than
    // guess at one. This is the fallback taken when session resolution failed,
    // so it is the branch most likely to run during a cold start.
    unawaited(
      _navigateWhenReady(
        () => Get.offAllNamed(AppRoutes.main, arguments: arguments),
      ),
    );
  }

  /// Forgets what this session handled, without going deaf.
  ///
  /// Sign-out used to call [dispose], which cancels the app-link
  /// subscription — and nothing ever called [init] again, so for the rest of
  /// the process the app received no links at all. That is the exact state a
  /// user is in when they need a reset most: they signed out, asked for the
  /// link from the login screen, and tapped it while the app was still alive
  /// in the background. The link reached `MainActivity` (launchMode is
  /// singleTop, so it arrives as a new intent, not a fresh start) and was
  /// dropped with no listener to receive it — the app just came to the
  /// foreground on the login screen, which is precisely "l'application
  /// s'ouvre directement".
  ///
  /// Only the per-session state is cleared here. [dispose] stays for real
  /// teardown, which in practice means tests.
  static void resetForNewSession() {
    _handledOobCodes.clear();
    _lastVideoLinkKey = null;
    _lastVideoLinkAt = null;
    PasswordResetFlow.end();
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _appLinks = null;
    _initialized = false;
    _isInitializing = false;
    _handledOobCodes.clear();
    _lastVideoLinkKey = null;
    _lastVideoLinkAt = null;
    await _verifiedCtrl?.close();
    _verifiedCtrl = null;
  }
}
