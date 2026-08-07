import 'package:adfoot/widgets/ad_feedback.dart';

void showSuccessToast(String message) {
  AdFeedback.success('Action confirmée', message);
}

void showErrorToast(String message) {
  AdFeedback.error('Action impossible', message);
}

void showInfoToast(String message) {
  AdFeedback.info('À noter', message);
}
