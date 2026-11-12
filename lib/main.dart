import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'config/app_bootstrap.dart';
import 'config/app_routes.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/locale_preference.dart';
import 'l10n/video_ui_translations.dart';
import 'theme/ad_colors.dart';
import 'theme/app_theme.dart';

// resolveAppLocale (and applyLocalePreference, used by the language picker
// in Outils) live in l10n/locale_preference.dart, not here -- re-exported so
// existing callers of `package:adfoot/main.dart` keep working unchanged.
export 'l10n/locale_preference.dart' show resolveAppLocale;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runZonedGuarded(
    () => runApp(const AppStartupGate()),
    AppBootstrap.reportZoneError,
  );
}

/// Renders immediately while the services required by [MyApp] start.
///
/// Firebase is still required before session routing begins, but waiting for
/// it before `runApp()` kept users on the native splash through every retry
/// and platform-channel delay. The gate gives Flutter its first frame first,
/// then installs the real app only when the existing bootstrap has finished.
class AppStartupGate extends StatefulWidget {
  const AppStartupGate({super.key, this.bootstrap, this.readyBuilder});

  final Future<void> Function()? bootstrap;
  final Widget Function()? readyBuilder;

  @override
  State<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<AppStartupGate> {
  bool _ready = false;
  bool _starting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    if (mounted && _error != null) {
      setState(() => _error = null);
    }

    try {
      await (widget.bootstrap ?? AppBootstrap.initialize)();
      Intl.defaultLocale = resolveAppLocale().languageCode == 'en'
          ? 'en_US'
          : 'fr_FR';
      if (mounted) {
        setState(() => _ready = true);
      }
    } catch (error, stack) {
      AppBootstrap.reportZoneError(error, stack);
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      _starting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return widget.readyBuilder?.call() ?? const MyApp();
    }

    // The same delegates and locale resolution the real app uses. Before
    // `LocalePreferenceStore` has finished loading, `resolveAppLocale()`
    // answers from the device; by the time the retry screen can appear the
    // stored preference is in memory, because bootstrap reads it before it
    // touches Firebase. Either way the shell every cold start goes through
    // stops being French-only.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: resolveAppLocale(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: _error == null
          ? const _StartupLoadingScreen()
          : _StartupRetryScreen(onRetry: _start),
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AdColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AdColors.brand),
              const SizedBox(height: 16),
              Text(
                l10n.startupPreparingMessage,
                style: const TextStyle(color: AdColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupRetryScreen extends StatelessWidget {
  const _StartupRetryScreen({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
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
                Text(
                  l10n.startupConnectionFailedTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.startupConnectionFailedMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AdColors.onSurfaceMuted),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => onRetry(),
                  child: Text(l10n.commonRetry),
                ),
              ],
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
      // Resolved from the device locale -- see [resolveAppLocale]. Passing
      // the resolved value directly (rather than `null`, which would leave
      // it to Flutter's own resolution) is what also makes `Get.locale`
      // reflect it, which the `VideoUiStrings` `.tr` catalog below depends
      // on to pick French vs. English.
      locale: resolveAppLocale(),
      fallbackLocale: const Locale('fr'),
      // Traductions GetX pour VideoUiStrings : ce catalogue est lu depuis des
      // controleurs/services sans BuildContext, ou AppLocalizations.of(context)
      // n'est pas utilisable. Voir lib/l10n/video_ui_translations.dart.
      translations: VideoUiTranslations(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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
