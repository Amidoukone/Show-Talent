import 'package:flutter/material.dart';
import 'package:get/get.dart';

void showSuccessToast(String message) {
  Get.snackbar(
    '',
    '',
    titleText: Row(
      children: const [
        Icon(Icons.check_circle, color: Colors.white, size: 24),
        SizedBox(width: 8),
        Text(
          'Succès 🎉',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    ),
    messageText: Text(
      message,
      style: const TextStyle(color: Colors.white, fontSize: 16),
    ),
    backgroundColor: Colors.green.shade600,
    snackPosition: SnackPosition.TOP,
    margin: const EdgeInsets.all(16),
    borderRadius: 16,
    duration: const Duration(seconds: 3),
    animationDuration: const Duration(milliseconds: 500),
    forwardAnimationCurve: Curves.easeOutBack,
    reverseAnimationCurve: Curves.easeInBack,
    isDismissible: true,
    overlayBlur: 1.5,
    overlayColor: Colors.black.withOpacity(0.2),
  );
}
