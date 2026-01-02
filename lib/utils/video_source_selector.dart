import 'package:adfoot/models/video.dart';

class VideoSourceSelector {
  static String chooseUrl({
    required String fallbackUrl,
    required List<VideoSource> sources,
    required bool adaptiveEnabled,
    required bool highBandwidth,
    bool preferHls = false,
  }) {
    final sanitizedSources = sources.where((s) => s.url.isNotEmpty).toList();
    if (!adaptiveEnabled || sanitizedSources.isEmpty) {
      if (fallbackUrl.isNotEmpty) return fallbackUrl;
      return sanitizedSources.isNotEmpty ? sanitizedSources.first.url : '';
    }

    if (preferHls) {
      final hlsSources = sanitizedSources.where((s) => s.isHls).toList()
        ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
      if (hlsSources.isNotEmpty) {
        return hlsSources.first.url;
      }
    }

    final sorted = [...sanitizedSources]
      ..sort((a, b) => (a.height ?? 0).compareTo(b.height ?? 0));

    if (highBandwidth) {
      return (sorted.lastWhere((s) => (s.height ?? 720) >= 600, orElse: () => sorted.last))
          .url;
    }

    return (sorted.firstWhere((s) => (s.height ?? 480) <= 540, orElse: () => sorted.first))
        .url;
  }
}