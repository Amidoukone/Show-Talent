import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'config/app_bootstrap.dart';
import 'config/app_routes.dart';
import 'theme/ad_colors.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    Intl.defaultLocale = 'fr_FR';
    await _bootstrapAndRun();
  }, AppBootstrap.reportZoneError);
}

// AppBootstrap.initialize() already retries a flaky first Firebase call,
// but if it still fails (e.g. no network at all on a cold start), the app
// must not silently exit before runApp() ever executes -- that reads to
// the user as the app closing itself with no explanation and no way to
// recover. Fall back to a minimal screen offering a manual retry instead.
Future<void> _bootstrapAndRun() async {
  try {
    await AppBootstrap.initialize();
    runApp(const MyApp());
  } catch (error, stack) {
    AppBootstrap.reportZoneError(error, stack);
    runApp(_StartupRetryApp(onRetry: _bootstrapAndRun));
  }
}

class _StartupRetryApp extends StatelessWidget {
  const _StartupRetryApp({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        backgroundColor: AdColors.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: AdColors.onSurfaceMuted,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Connexion impossible',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Adfoot n’a pas pu se connecter. '
                    'Vérifiez votre réseau puis réessayez.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AdColors.onSurfaceMuted),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => onRetry(),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdfootApp extends StatelessWidget {
  const AdfootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Adfoot',
      debugShowCheckedModeBanner: false,
      navigatorKey: Get.key,
      theme: AppTheme.light(),
      locale: const Locale('fr', 'FR'),
      fallbackLocale: const Locale('fr', 'FR'),
      supportedLocales: const <Locale>[
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      defaultTransition: Transition.fadeIn,
      color: AdColors.brand,
      builder: (context, child) {
        final Widget safeChild = child ?? const SizedBox.shrink();

        final wrapped = GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: () {
            final focus = FocusManager.instance.primaryFocus;
            if (focus?.hasFocus == true) {
              focus?.unfocus();
            }
          },
          child: safeChild,
        );

        final mq = MediaQuery.of(context);
        // Respect the system text-size setting for low-vision users instead
        // of flattening it to near-1.0 — only guard the extremes so a very
        // large system setting can't overflow layouts we haven't audited.
        final scaleValue = mq.textScaler.scale(1.0).clamp(0.85, 1.6);

        final mediaWrapped = MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(scaleValue),
            padding: mq.padding,
            viewPadding: mq.viewPadding,
            viewInsets: mq.viewInsets,
            systemGestureInsets: mq.systemGestureInsets,
          ),
          child: wrapped,
        );

        return ScrollConfiguration(
          behavior: const _AppScrollBehavior(),
          child: mediaWrapped,
        );
      },
      initialRoute: AppRoutes.splash,
      getPages: AppRoutes.pages,
    );
  }
}

class MyApp extends AdfootApp {
  const MyApp({super.key});
}

class _AppScrollBehavior extends ScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return const BouncingScrollPhysics();
    }
    return const ClampingScrollPhysics();
  }
}
