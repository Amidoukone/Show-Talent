import 'package:adfoot/models/video.dart';

class VideoSourceSelector {
  static List<VideoSource> _sanitize(List<VideoSource> sources) =>
      sources.where((source) => source.url.isNotEmpty).toList();

  static List<VideoSource> _nonHlsSources(List<VideoSource> sources) =>
      sources.where((source) => !source.isHls).toList();

  static bool _isHlsUrl(String url) => url.toLowerCase().contains('.m3u8');

  static List<VideoSource> _sortedByHeight(List<VideoSource> sources) =>
      [...sources]..sort((a, b) => (a.height ?? 0).compareTo(b.height ?? 0));

  static VideoSource? _bestAtLeast(List<VideoSource> list, int minHeight) {
    for (final source in list) {
      if ((source.height ?? 0) >= minHeight) {
        return source;
      }
    }
    return list.isNotEmpty ? list.last : null;
  }

  static VideoSource? _bestAtMost(List<VideoSource> list, int maxHeight) {
    for (final source in list.reversed) {
      if ((source.height ?? 0) <= maxHeight) {
        return source;
      }
    }
    return list.isNotEmpty ? list.first : null;
  }

  static VideoSource? _preferredSingleRenditionSource(
    List<VideoSource> sources,
  ) {
    final sorted = _sortedByHeight(sources);
    return sorted.isNotEmpty ? sorted.last : null;
  }

  static VideoSource? _fallbackSource({
    required String fallbackUrl,
    required List<VideoSource> candidateSources,
  }) {
    final canonicalSource = _preferredSingleRenditionSource(candidateSources);

    if (fallbackUrl.isEmpty || _isHlsUrl(fallbackUrl)) {
      return canonicalSource;
    }

    for (final source in candidateSources) {
      if (source.url == fallbackUrl) {
        return source;
      }
    }

    return canonicalSource ?? VideoSource(url: fallbackUrl);
  }

  static VideoSource? preferredSource({
    required String fallbackUrl,
    required List<VideoSource> sources,
    required bool adaptiveEnabled,
    required bool highBandwidth,
    bool preferHls = false,
  }) {
    final sanitizedSources = _sanitize(sources);
    final candidateSources = _nonHlsSources(sanitizedSources);

    if (!adaptiveEnabled || candidateSources.isEmpty) {
      return _fallbackSource(
        fallbackUrl: fallbackUrl,
        candidateSources: candidateSources,
      );
    }

    final sorted = _sortedByHeight(candidateSources);

    if (highBandwidth) {
      return _bestAtLeast(sorted, 700) ?? sorted.last;
    }

    return _bestAtMost(sorted, 540) ?? sorted.first;
  }

  static VideoSource? sourceForUrl({
    required String url,
    required List<VideoSource> sources,
  }) {
    if (url.isEmpty || _isHlsUrl(url)) {
      return null;
    }

    final sanitizedSources = _nonHlsSources(_sanitize(sources));
    for (final source in sanitizedSources) {
      if (source.url == url) {
        return source;
      }
    }

    return null;
  }

  static String chooseUrl({
    required String fallbackUrl,
    required List<VideoSource> sources,
    required bool adaptiveEnabled,
    required bool highBandwidth,
    bool preferHls = false,
  }) {
    return preferredSource(
          fallbackUrl: fallbackUrl,
          sources: sources,
          adaptiveEnabled: adaptiveEnabled,
          highBandwidth: highBandwidth,
          preferHls: preferHls,
        )?.url ??
        '';
  }

  /// Returns sources ordered by priority for playback and fallback.
  static List<VideoSource> prioritizedSources({
    required String fallbackUrl,
    required List<VideoSource> sources,
    required bool adaptiveEnabled,
    required bool highBandwidth,
    bool preferHls = false,
  }) {
    final sanitizedSources = _sanitize(sources);
    final candidateSources = _nonHlsSources(sanitizedSources);

    if (!adaptiveEnabled || candidateSources.isEmpty) {
      final primary = preferredSource(
        fallbackUrl: fallbackUrl,
        sources: sources,
        adaptiveEnabled: adaptiveEnabled,
        highBandwidth: highBandwidth,
        preferHls: preferHls,
      );

      return _dedupe([
        if (primary != null) primary,
      ]);
    }

    final mp4Sources = _sortedByHeight(
      candidateSources.where((source) => !source.isHls).toList(),
    );

    final preferred720 = _bestAtLeast(mp4Sources, 700);
    final preferred480 = _bestAtMost(mp4Sources, 540);
    final preferred360 = _bestAtMost(mp4Sources, 400);

    final ordered = <VideoSource>[
      if (highBandwidth) ...[
        if (preferred720 != null) preferred720,
        if (preferred480 != null) preferred480,
        ...mp4Sources.reversed,
      ] else ...[
        if (preferred480 != null) preferred480,
        if (preferred360 != null) preferred360,
        ...mp4Sources,
        ...mp4Sources.reversed,
      ],
      if (fallbackUrl.isNotEmpty && !_isHlsUrl(fallbackUrl))
        VideoSource(url: fallbackUrl),
    ];

    return _dedupe(ordered);
  }

  static List<VideoSource> _dedupe(List<VideoSource> list) {
    final seen = <String>{};
    final result = <VideoSource>[];

    for (final source in list) {
      if (source.url.isEmpty) continue;
      if (seen.add(source.url)) {
        result.add(source);
      }
    }
    return result;
  }
}
