import 'package:adfoot/widgets/ad_feedback.dart';

void showSuccessToast(String message) {
  AdFeedback.success('Succes', message);
}

void showErrorToast(String message) {
  AdFeedback.error('Erreur', message);
}

void showInfoToast(String message) {
  AdFeedback.info('Information', message);
}
