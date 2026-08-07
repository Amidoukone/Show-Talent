import 'package:adfoot/widgets/ad_feedback.dart';

class AdSnackbar {
  static void success(String title, String message) =>
      AdFeedback.success(title, message);

  static void info(String title, String message) =>
      AdFeedback.info(title, message);

  static void warning(String title, String message) =>
      AdFeedback.warning(title, message);

  static void error(String title, String message) =>
      AdFeedback.error(title, message);
}
