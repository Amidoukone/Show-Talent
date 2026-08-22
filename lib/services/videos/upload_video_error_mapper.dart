import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';

import 'package:adfoot/services/videos/data/upload_client.dart';
import 'package:adfoot/utils/video_publication_quota.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

class UploadVideoErrorMapper {
  UploadVideoErrorMapper._();

  /// True when `createUploadSession` refused because the account already
  /// holds its full allowance of public videos.
  ///
  /// `resource-exhausted` alone is not enough: the same code carries four
  /// different refusals from `assertUploadRateLimits` (concurrent uploads,
  /// daily uploads, pending reviews, public videos) plus the global upload
  /// kill switch, and only this one is answered by asking the agency to
  /// raise a cap.
  ///
  /// Structured `details` are read first so the day the callable starts
  /// sending them the match stops depending on prose at all. Until then the
  /// message is the only discriminator available, so it is normalised for
  /// accents — the deployed text is accent-free ASCII, and a French
  /// rewording of it would not be.
  static bool isPublicVideoQuotaFailure(Object error) {
    if (error is! FirebaseFunctionsException) return false;
    if (error.code != 'resource-exhausted') return false;

    final details = error.details;
    if (details is Map && details['reason'] == 'public_video_quota') {
      return true;
    }

    final normalized = _stripAccents((error.message ?? '').toLowerCase());
    return normalized.contains('video') && normalized.contains('publique');
  }

  static String _stripAccents(String value) {
    const replacements = <String, String>{
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };

    var normalized = value;
    replacements.forEach((accented, plain) {
      normalized = normalized.replaceAll(accented, plain);
    });
    return normalized;
  }

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

      if (_isTransientCallableCode(error.code)) {
        return VideoUiStrings.uploadConnectionUnstable;
      }

      // Before the pass-through below: the server's own wording is
      // accent-free and tells the player to "archiver une video", which is
      // not something the application lets anyone do.
      if (isPublicVideoQuotaFailure(error)) {
        return VideoUiStrings.uploadQuotaReachedShort(
          VideoPublicationQuota.maxPublishedVideos,
        );
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

    if (error is UploadClientException) {
      return _uploadClientUserMessage(error);
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

  static bool _isTransientCallableCode(String code) {
    switch (code) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
      case 'aborted':
      case 'cancelled':
        return true;
      default:
        return false;
    }
  }

  // A statusCode means this came from _sendChunkWithRetry exhausting its
  // retries: its message embeds a raw diagnostic ("... statut HTTP 500.",
  // Dio exception text) meant for logs, not end users. Messages with no
  // statusCode (file missing/empty, expired thumbnail ticket, the
  // session-refresh cap) are already clean, user-appropriate French text
  // written for display, so pass those through as-is.
  static String _uploadClientUserMessage(UploadClientException error) {
    final statusCode = error.statusCode;
    if (statusCode == null) {
      final message = error.message.trim();
      return message.isNotEmpty ? message : VideoUiStrings.uploadUnknownError;
    }
    if (statusCode >= 500) {
      return VideoUiStrings.uploadServiceUnavailable;
    }
    if (statusCode == 401 || statusCode == 403) {
      return VideoUiStrings.uploadPermissionDenied;
    }
    return VideoUiStrings.uploadConnectionUnstable;
  }
}
