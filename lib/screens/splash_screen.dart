import 'dart:async';

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:adfoot/services/auth/auth_diagnostics.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/auth/password_reset_flow.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/auth_controller.dart';
import '../controller/user_controller.dart';
import 'package:adfoot/services/app_logger.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.fallbackInitializationDelay = const Duration(milliseconds: 600),
    this.fallbackRouteBuilder,
  });

  final Duration fallbackInitializationDelay;
  final Future<Widget?> Function()? fallbackRouteBuilder;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthSessionService _authSessionService = AuthSessionService();

  static const Duration _authWatchdogDelay = Duration(seconds: 8);
  static const Duration _sessionResolveTimeout = Duration(seconds: 18);

  bool _navigating = false;
  late final bool _authControllerPresent;
  Timer? _authWatchdogTimer;

  @override
  void initState() {
    super.initState();
    _authControllerPresent = Get.isRegistered<AuthController>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Get.find<UserController>().kickstart();
      } catch (error) {
        AppLogger.debug('Splash kickstart error: $error');
      }
    });

    if (!_authControllerPresent) {
      unawaited(_initializeFallback());
    } else {
      _authWatchdogTimer = Timer(_authWatchdogDelay, () {
        unawaited(_initializeFallback(useSafeSessionResolve: true));
      });
    }
  }

  @override
  void dispose() {
    _authWatchdogTimer?.cancel();
    super.dispose();
  }

  bool get _isStillOnSplashRoute {
    final route = Get.currentRoute;
    return route.isEmpty || route == AppRoutes.splash;
  }

  bool get _canRunFallback {
    // The second owner of the cold-start race a tapped reset link creates:
    // this fallback resolves the session and replaces the stack, which used
    // to take the reset screen away again. See [PasswordResetFlow].
    if (PasswordResetFlow.isInProgress) {
      return false;
    }

    return mounted && !_navigating && _isStillOnSplashRoute;
  }

  Future<void> _initializeFallback({bool useSafeSessionResolve = false}) async {
    await Future.delayed(widget.fallbackInitializationDelay);
    if (!_canRunFallback) {
      return;
    }

    if (widget.fallbackRouteBuilder != null) {
      final fallbackPage = await widget.fallbackRouteBuilder!.call();
      if (!_canRunFallback) {
        return;
      }
      if (fallbackPage != null) {
        return _safeOffAll(fallbackPage);
      }
      return;
    }

    try {
      final snapshot = await _resolveSessionForFallback(
        useSafeSessionResolve: useSafeSessionResolve,
      );
      if (!_canRunFallback) {
        return;
      }

      return _safeOffAllDestination(snapshot.destination);
    } catch (error) {
      // The app could not decide where this launch belongs, so it signs
      // out and shows login. To the user that is "l'application m'a
      // déconnecté au démarrage", and it left no trace at all.
      AuthDiagnostics.failure(
        'startup session resolution failed; signing out',
        stage: 'splash_fallback',
        error: error,
      );
      try {
        await _authSessionService.signOut();
      } catch (signOutError) {
        AppLogger.debug('Splash fallback sign-out error: $signOutError');
      }
      return _safeOffAll(const LoginScreen());
    }
  }

  Widget _pageForDestination(AuthSessionDestination destination) {
    switch (destination) {
      case AuthSessionDestination.login:
        return const LoginScreen();
      case AuthSessionDestination.verifyEmail:
        return const VerifyEmailScreen();
      case AuthSessionDestination.main:
        return const MainScreen();
    }
  }

  Future<AuthSessionSnapshot> _resolveSessionForFallback({
    required bool useSafeSessionResolve,
  }) {
    final currentUser = _authSessionService.currentUser;
    final sessionFuture = useSafeSessionResolve
        ? _authSessionService.resolveSessionSafely(
            currentUser,
            waitForVerifiedUserDocument: true,
            syncVerifiedUserRecord: true,
            updateLastLogin: true,
            signOutOnInvalid: true,
          )
        : _authSessionService.resolveSession(
            currentUser,
            waitForVerifiedUserDocument: true,
            syncVerifiedUserRecord: true,
            updateLastLogin: true,
            signOutOnInvalid: true,
          );

    return sessionFuture.timeout(
      _sessionResolveTimeout,
      onTimeout: () {
        final fallbackUser = _authSessionService.currentUser ?? currentUser;
        if (fallbackUser == null) {
          return const AuthSessionSnapshot(
            destination: AuthSessionDestination.login,
          );
        }

        return AuthSessionSnapshot(
          destination: fallbackUser.emailVerified
              ? AuthSessionDestination.main
              : AuthSessionDestination.verifyEmail,
          firebaseUser: fallbackUser,
        );
      },
    );
  }

  Future<void> _safeOffAllDestination(
    AuthSessionDestination destination,
  ) async {
    try {
      await _safeOffAllNamed(destination.routeName);
    } catch (error) {
      AuthDiagnostics.handled(
        'named startup navigation failed; falling back to a direct page',
        stage: 'splash_fallback',
        error: error,
      );
      await _safeOffAll(_pageForDestination(destination));
    }
  }

  /// Installs [routeName], or throws so the caller can fall back to a page.
  ///
  /// The same trap as `UserController._safeOffAllNamed`, and here it had no
  /// timeout to end it: `Get.offAllNamed` hands back the pushed route's *pop*
  /// future, and a root route is never popped. Awaiting it meant this method
  /// never returned — `_navigating` stayed true for the life of the screen,
  /// the `finally` never ran, and the `catch` in [_safeOffAllDestination],
  /// whose whole job is to fall back to a direct page when named routing
  /// fails, could never be reached. It was dead code from the day it was
  /// written.
  ///
  /// Waiting one frame and then checking where the app actually landed is
  /// what makes that fallback real.
  Future<void> _safeOffAllNamed(String routeName) async {
    if (_navigating) {
      return;
    }

    _navigating = true;
    try {
      final navigation = Get.offAllNamed(routeName);
      if (navigation != null) {
        unawaited(navigation.then((_) {}, onError: (Object _) {}));
      }

      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );

      if (Get.currentRoute != routeName) {
        throw StateError(
          'named navigation did not land on $routeName; '
          'still on ${Get.currentRoute}',
        );
      }
    } finally {
      _navigating = false;
    }
  }

  Future<void> _safeOffAll(Widget page) async {
    if (_navigating) {
      return;
    }

    _navigating = true;
    try {
      // Not awaited, for the reason above. This is the last resort of the
      // startup path, so it must not be the thing that stalls it.
      final navigation = Get.offAll(() => page);
      if (navigation != null) {
        unawaited(navigation.then((_) {}, onError: (Object _) {}));
      }

      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AdColors.surface,
      body: Center(child: CircularProgressIndicator(color: AdColors.brand)),
    );
  }
}
