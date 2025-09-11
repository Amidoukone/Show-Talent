import 'package:flutter/material.dart';
import 'package:get/get.dart';

const _defaultMargin = EdgeInsets.all(16.0);
const _defaultBorderRadius = 16.0;
const _defaultAnimationDuration = Duration(milliseconds: 500);
const _defaultOverlayBlur = 1.5;

void showSuccessToast(String message) {
  Get.snackbar(
    '',
    '',
    titleText: Row(
      children: const [
        Icon(Icons.check_circle, color: Colors.white, size: 24),
        SizedBox(width: 8),
        Text(
          'Succès !',
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
    margin: _defaultMargin,
    borderRadius: _defaultBorderRadius,
    duration: const Duration(seconds: 3),
    animationDuration: _defaultAnimationDuration,
    forwardAnimationCurve: Curves.easeOutBack,
    reverseAnimationCurve: Curves.easeInBack,
    isDismissible: true,
    overlayBlur: _defaultOverlayBlur,
    overlayColor: Colors.black.withOpacity(0.2),
  );
}

void showErrorToast(String message) {
  Get.snackbar(
    '',
    '',
    titleText: Row(
      children: const [
        Icon(Icons.error_outline, color: Colors.white, size: 24),
        SizedBox(width: 8),
        Text(
          'Erreur ⚠️',
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
    backgroundColor: Colors.red.shade700,
    snackPosition: SnackPosition.TOP,
    margin: _defaultMargin,
    borderRadius: _defaultBorderRadius,
    duration: const Duration(seconds: 4),
    animationDuration: _defaultAnimationDuration,
    forwardAnimationCurve: Curves.easeOutBack,
    reverseAnimationCurve: Curves.easeInBack,
    isDismissible: true,
    overlayBlur: _defaultOverlayBlur,
    overlayColor: Colors.black.withOpacity(0.25),
  );
}

void showInfoToast(String message) {
  Get.snackbar(
    '',
    '',
    titleText: Row(
      children: const [
        Icon(Icons.info_outline, color: Colors.white, size: 24),
        SizedBox(width: 8),
        Text(
          'Info 🕒',
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
    backgroundColor: Colors.blueGrey.shade700,
    snackPosition: SnackPosition.TOP,
    margin: _defaultMargin,
    borderRadius: _defaultBorderRadius,
    duration: const Duration(seconds: 4),
    animationDuration: _defaultAnimationDuration,
    forwardAnimationCurve: Curves.easeOutBack,
    reverseAnimationCurve: Curves.easeInBack,
    isDismissible: true,
    overlayBlur: _defaultOverlayBlur,
    overlayColor: Colors.black.withOpacity(0.2),
  );
}
