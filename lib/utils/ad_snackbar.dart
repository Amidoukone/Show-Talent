import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/ad_colors.dart';

class AdSnackbar {
  static void success(String title, String message) => _show(title, message, AdColors.success);
  static void info(String title, String message) => _show(title, message, AdColors.brand);
  static void warning(String title, String message) => _show(title, message, AdColors.warning);
  static void error(String title, String message) => _show(title, message, AdColors.error);

  static void _show(String title, String message, Color color) {
    Get.snackbar(
      title,
      message,
      backgroundColor: color,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(12),
      borderRadius: 12,
      duration: const Duration(seconds: 3),
    );
  }
}
