import 'package:adfoot/screens/login_screen.dart';
import 'package:adfoot/screens/main_screen.dart';
import 'package:adfoot/screens/verify_email_screen.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/auth_controller.dart';
import '../controller/user_controller.dart';

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

  bool _navigating = false;
  late final bool _authControllerPresent;

  @override
  void initState() {
    super.initState();
    _authControllerPresent = Get.isRegistered<AuthController>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Get.find<UserController>().kickstart();
      } catch (_) {}
    });

    if (!_authControllerPresent) {
      _initializeFallback();
    }
  }

  Future<void> _initializeFallback() async {
    await Future.delayed(widget.fallbackInitializationDelay);

    if (widget.fallbackRouteBuilder != null) {
      final fallbackPage = await widget.fallbackRouteBuilder!.call();
      if (fallbackPage != null) {
        return _safeOffAll(fallbackPage);
      }
      return;
    }

    try {
      final snapshot = await _authSessionService.resolveSession(
        _authSessionService.currentUser,
        waitForVerifiedUserDocument: true,
        syncVerifiedUserRecord: true,
        updateLastLogin: true,
        signOutOnInvalid: true,
      );

      return _safeOffAll(_pageForDestination(snapshot.destination));
    } catch (error) {
      debugPrint('Splash fallback error: $error');
      try {
        await _authSessionService.signOut();
      } catch (_) {}
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

  Future<void> _safeOffAll(Widget page) async {
    if (_navigating) {
      return;
    }

    _navigating = true;
    try {
      await Get.offAll(() => page);
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AdColors.surface,
      body: Center(
        child: CircularProgressIndicator(color: AdColors.brand),
      ),
    );
  }
}
