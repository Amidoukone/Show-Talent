import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';

import 'package:adfoot/services/videos/data/upload_client.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

class UploadVideoErrorMapper {
  UploadVideoErrorMapper._();

  static String failureCode(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.code;
    }
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) return 'http-$statusCode';
      return error.type.name;
    }
    if (error is UploadClientException) {
      return error.statusCode != null
          ? 'upload-client-${error.statusCode}'
          : 'upload-client';
    }
    return 'upload-error';
  }

  static String toUserMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      if (error.code == 'unauthenticated') {
        return VideoUiStrings.uploadAuthRequired;
      }

      final message = (error.message ?? '').trim();
      if (message.isNotEmpty) {
        return message;
      }

      switch (error.code) {
        case 'permission-denied':
          return VideoUiStrings.uploadPermissionDenied;
        case 'resource-exhausted':
          return VideoUiStrings.uploadServiceUnavailable;
        case 'failed-precondition':
          return VideoUiStrings.uploadPreconditionFailed;
        default:
          return VideoUiStrings.uploadServerError;
      }
    }

    final normalized = error.toString();
    if (normalized.startsWith('Exception: ')) {
      return normalized.substring('Exception: '.length);
    }
    if (normalized.trim().isEmpty) {
      return VideoUiStrings.uploadUnknownError;
    }
    return normalized;
  }
}
