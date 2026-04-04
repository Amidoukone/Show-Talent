import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/ad_colors.dart';

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
      backgroundColor: AdColors.success,
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
      backgroundColor: AdColors.error,
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
      backgroundColor: AdColors.warning,
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
      backgroundColor: AdColors.surfaceCardAlt,
      duration: duration,
    );
  }

  static void _show({
    required String title,
    required String message,
    required Color backgroundColor,
    required Duration duration,
  }) {
    Get.snackbar(
      title,
      message,
      backgroundColor: backgroundColor,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: duration,
      margin: const EdgeInsets.all(12),
      borderRadius: 12,
    );
  }
}
