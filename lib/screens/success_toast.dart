import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:get/get.dart';

void showSuccessToast(String message) {
  AdFeedback.success('actionConfirmedTitle'.tr, message);
}

void showErrorToast(String message) {
  AdFeedback.error('actionImpossibleTitle'.tr, message);
}

void showInfoToast(String message) {
  AdFeedback.info('noteTitle'.tr, message);
}
