import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'config/app_bootstrap.dart';
import 'config/app_routes.dart';
import 'theme/ad_colors.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    await AppBootstrap.initialize();
    runApp(const MyApp());
  }, AppBootstrap.reportZoneError);
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
        final scaleValue = mq.textScaler.scale(1.0).clamp(0.85, 1.15);

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
