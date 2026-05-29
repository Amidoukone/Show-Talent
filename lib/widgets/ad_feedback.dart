import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/ad_colors.dart';
import '../theme/ad_tokens.dart';

class AdFeedback {
  AdFeedback._();

  static void success(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      title: title,
      message: message,
      accentColor: AdColors.success,
      icon: Icons.check_rounded,
      duration: duration,
    );
  }

  static void error(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      title: title,
      message: message,
      accentColor: AdColors.error,
      icon: Icons.close_rounded,
      duration: duration,
    );
  }

  static void warning(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      title: title,
      message: message,
      accentColor: AdColors.warning,
      icon: Icons.priority_high_rounded,
      duration: duration,
    );
  }

  static void info(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      title: title,
      message: message,
      accentColor: AdColors.info,
      icon: Icons.info_outline_rounded,
      duration: duration,
    );
  }

  static void _show({
    required String title,
    required String message,
    required Color accentColor,
    required IconData icon,
    required Duration duration,
  }) {
    final resolvedTitle = title.trim();
    final resolvedMessage = message.trim();
    if (resolvedTitle.isEmpty && resolvedMessage.isEmpty) {
      return;
    }

    Get.showSnackbar(GetSnackBar(
      title: resolvedTitle,
      message: resolvedMessage,
      snackPosition: SnackPosition.BOTTOM,
      snackStyle: SnackStyle.FLOATING,
      backgroundColor: AdColors.surfaceCard.withValues(alpha: 0.96),
      borderColor: accentColor.withValues(alpha: 0.42),
      borderWidth: 1,
      borderRadius: AdRadius.lg,
      boxShadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.32),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
      duration: duration,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      padding: const EdgeInsets.symmetric(
        horizontal: AdSpacing.md,
        vertical: AdSpacing.sm,
      ),
      maxWidth: 560,
      isDismissible: true,
      dismissDirection: DismissDirection.horizontal,
      forwardAnimationCurve: Curves.easeOutCubic,
      reverseAnimationCurve: Curves.easeInCubic,
      animationDuration: AdMotion.normal,
      icon: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: accentColor.withValues(alpha: 0.28)),
        ),
        child: Icon(icon, color: accentColor, size: 19),
      ),
      shouldIconPulse: false,
      titleText: Text(
        resolvedTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AdColors.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1.18,
        ),
      ),
      messageText: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          resolvedMessage,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AdColors.onSurfaceMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ),
    ));
  }
}
