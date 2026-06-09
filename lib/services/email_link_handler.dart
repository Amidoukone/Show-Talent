import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
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
      _logDebug('EmailLinkHandler detected resetPassword link.');

      if (_handledOobCodes.contains(oob)) {
        _logDebug('EmailLinkHandler ignored duplicate resetPassword oobCode.');
        return false;
      }
      _handledOobCodes.add(oob);

      try {
        await FirebaseAuth.instance.verifyPasswordResetCode(oob);

        if (Get.isRegistered<GetMaterialApp>() ||
            Get.key.currentState != null) {
          Get.toNamed(
            AppRoutes.resetPassword,
            arguments: {'oobCode': oob},
          );
        } else {
          Future.delayed(const Duration(milliseconds: 300), () {
            Get.toNamed(
              AppRoutes.resetPassword,
              arguments: {'oobCode': oob},
            );
          });
        }

        return true;
      } on FirebaseAuthException catch (e) {
        _logDebug(
          'EmailLinkHandler resetPassword FirebaseAuthException: '
          '${e.code} ${e.message}',
        );
        return false;
      } catch (e) {
        _logDebug('EmailLinkHandler resetPassword unexpected: $e');
        return false;
      }
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
      _logDebug(
        'EmailLinkHandler verifyEmail FirebaseAuthException: '
        '${e.code} ${e.message}',
      );
      return false;
    } catch (e) {
      _logDebug('EmailLinkHandler verifyEmail unexpected: $e');
      return false;
    }
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
    if (Get.key.currentState != null) {
      Get.offAllNamed(AppRoutes.main, arguments: arguments);
      return;
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      Get.offAllNamed(AppRoutes.main, arguments: arguments);
    });
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
