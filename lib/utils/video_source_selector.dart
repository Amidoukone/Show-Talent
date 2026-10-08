import 'package:adfoot/models/video.dart';

class VideoSourceSelector {
  static List<VideoSource> _sanitize(List<VideoSource> sources) =>
      sources.where((source) => source.url.isNotEmpty && source.isMp4).toList();

  static bool _isMp4Url(String url) => url.toLowerCase().contains('.mp4');

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

    if (fallbackUrl.isEmpty || !_isMp4Url(fallbackUrl)) {
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
    // Unused on the `highBandwidth` branch — see [prioritizedSources] for why
    // a cap only means something on the non-high branch. Default of 540
    // reproduces the exact behaviour this had before the parameter existed.
    int lowBandwidthMaxHeight = 540,
  }) {
    final sanitizedSources = _sanitize(sources);
    final candidateSources = sanitizedSources;

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

    return _bestAtMost(sorted, lowBandwidthMaxHeight) ?? sorted.first;
  }

  static VideoSource? sourceForUrl({
    required String url,
    required List<VideoSource> sources,
  }) {
    if (url.isEmpty || !_isMp4Url(url)) {
      return null;
    }

    final sanitizedSources = _sanitize(sources);
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
    int lowBandwidthMaxHeight = 540,
  }) {
    return preferredSource(
          fallbackUrl: fallbackUrl,
          sources: sources,
          adaptiveEnabled: adaptiveEnabled,
          highBandwidth: highBandwidth,
          lowBandwidthMaxHeight: lowBandwidthMaxHeight,
        )?.url ??
        '';
  }

  /// Every playable source, lightest first — the inverse of the tier-based
  /// ordering [prioritizedSources] produces.
  ///
  /// For the one case where the tier is not the question: a rendition the
  /// network tier already deemed appropriate can still stall or miss its
  /// first frame on a connection too slow to sustain it. The tier has not
  /// changed between that failure and the retry, so asking
  /// [prioritizedSources] again hands back the exact candidate that just
  /// failed. This ignores the tier and starts from the smallest file the
  /// video has instead.
  static List<VideoSource> smallestFirstCandidates({
    required String fallbackUrl,
    required List<VideoSource> sources,
  }) {
    final ascending = _sortedByHeight(_sanitize(sources));
    return _dedupe([
      ...ascending,
      if (fallbackUrl.isNotEmpty && _isMp4Url(fallbackUrl))
        VideoSource(url: fallbackUrl),
    ]);
  }

  /// Returns sources ordered by priority for playback and fallback.
  ///
  /// [lowBandwidthMaxHeight] is the cap used on the non-`highBandwidth`
  /// branch only — defaults to 540, which reproduces this method's exact
  /// prior behaviour. A caller that knows the connection is not just
  /// "not high" but specifically the slowest tier can pass a stricter cap
  /// (e.g. 360) to ask for a lighter rendition from the first attempt,
  /// without touching what "medium" or "high" request.
  static List<VideoSource> prioritizedSources({
    required String fallbackUrl,
    required List<VideoSource> sources,
    required bool adaptiveEnabled,
    required bool highBandwidth,
    int lowBandwidthMaxHeight = 540,
  }) {
    final sanitizedSources = _sanitize(sources);
    final candidateSources = sanitizedSources;

    if (!adaptiveEnabled || candidateSources.isEmpty) {
      final primary = preferredSource(
        fallbackUrl: fallbackUrl,
        sources: sources,
        adaptiveEnabled: adaptiveEnabled,
        highBandwidth: highBandwidth,
        lowBandwidthMaxHeight: lowBandwidthMaxHeight,
      );

      return _dedupe([?primary]);
    }

    final mp4Sources = _sortedByHeight(candidateSources);

    final preferred720 = _bestAtLeast(mp4Sources, 700);
    final preferred480 = _bestAtMost(mp4Sources, 540);
    final preferred360 = _bestAtMost(mp4Sources, 400);
    final preferredAtLowCap = _bestAtMost(mp4Sources, lowBandwidthMaxHeight);

    final ordered = <VideoSource>[
      if (highBandwidth) ...[
        ?preferred720,
        ?preferred480,
        ...mp4Sources.reversed,
      ] else ...[
        ?preferredAtLowCap,
        ?preferred360,
        ...mp4Sources,
        ...mp4Sources.reversed,
      ],
      if (fallbackUrl.isNotEmpty && _isMp4Url(fallbackUrl))
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
