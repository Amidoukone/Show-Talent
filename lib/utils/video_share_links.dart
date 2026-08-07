import '../config/app_environment.dart';

class VideoShareLinks {
  VideoShareLinks._();

  static final RegExp _validVideoId = RegExp(r'^[A-Za-z0-9_-]{6,80}$');

  static Uri? buildVideoUri(String videoId) {
    final normalizedId = normalizeVideoId(videoId);
    if (normalizedId == null) {
      return null;
    }

    final base = AppEnvironmentConfig.videoShareBaseUri;
    final baseSegments = base.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);

    return base.replace(
      pathSegments: <String>[
        ...baseSegments,
        'v',
        normalizedId,
      ],
      queryParameters: null,
      fragment: null,
    );
  }

  static String? buildVideoUrl(String videoId) =>
      buildVideoUri(videoId)?.toString();

  static String? extractVideoId(Uri uri) {
    if (uri.scheme != 'https') {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (!AppEnvironmentConfig.videoShareAllowedHosts.contains(host)) {
      return null;
    }

    final segments = uri.pathSegments;
    if (segments.length < 2 || segments.first != 'v') {
      return null;
    }

    return normalizeVideoId(segments[1]);
  }

  static String? normalizeVideoId(String rawVideoId) {
    final normalized = rawVideoId.trim();
    if (normalized.isEmpty || !_validVideoId.hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }
}
