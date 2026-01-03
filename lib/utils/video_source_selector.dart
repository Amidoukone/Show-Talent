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
      return (sorted.lastWhere(
        (s) => (s.height ?? 720) >= 600,
        orElse: () => sorted.last,
      )).url;
    }

    return (sorted.firstWhere(
      (s) => (s.height ?? 480) <= 540,
      orElse: () => sorted.first,
    )).url;
  }

  /// Retourne une liste de sources classées par priorité, utile pour :
  /// - fallback automatique (si une URL ne marche pas)
  /// - préchargement / orchestrateur
  /// - stratégie adaptative plus robuste que "une seule URL"
  ///
  /// Ordre typique :
  /// - (optionnel) HLS préféré (si preferHls = true)
  /// - MP4 "haute" (>= ~720) si dispo
  /// - MP4 "moyenne/basse" (<= ~480/520) si dispo
  /// - fallbackUrl (si fourni)
  static List<VideoSource> prioritizedSources({
    required String fallbackUrl,
    required List<VideoSource> sources,
    required bool adaptiveEnabled,
    required bool highBandwidth,
    bool preferHls = false,
  }) {
    final sanitizedSources = sources.where((s) => s.url.isNotEmpty).toList();

    // Si pas d’adaptatif, on renvoie juste quelque chose de stable + fallback.
    if (!adaptiveEnabled || sanitizedSources.isEmpty) {
      final primary = sanitizedSources.isNotEmpty ? sanitizedSources.first : null;
      return _dedupe([
        if (primary != null) primary,
        if (fallbackUrl.isNotEmpty) VideoSource(url: fallbackUrl),
      ]);
    }

    // Sépare HLS vs MP4 (ou non-HLS), puis trie décroissant par résolution.
    final hlsSources = sanitizedSources.where((s) => s.isHls).toList()
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));

    final mp4Sources = sanitizedSources.where((s) => !s.isHls).toList()
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));

    // Choisit la "meilleure" source dont la hauteur est >= minHeight.
    VideoSource? bestAtLeast(List<VideoSource> list, int minHeight) {
      for (final s in list) {
        if ((s.height ?? 0) >= minHeight) return s;
      }
      return list.isNotEmpty ? list.first : null;
    }

    // Choisit la "meilleure" source dont la hauteur est <= maxHeight.
    VideoSource? bestAtMost(List<VideoSource> list, int maxHeight) {
      for (final s in list.reversed) {
        if ((s.height ?? 0) <= maxHeight) return s;
      }
      return list.isNotEmpty ? list.last : null;
    }

    // HLS : si demandé, on met un HLS en premier.
    // - En highBandwidth, on prend le plus "haut" (first)
    // - Sinon, le plus "bas" (last) pour limiter la bande passante
    final preferredHls = preferHls
        ? (hlsSources.isNotEmpty
            ? (highBandwidth ? hlsSources.first : hlsSources.last)
            : null)
        : null;

    // MP4 : une "haute" + une "basse" (si elles existent)
    final preferred720 = bestAtLeast(mp4Sources, 700);
    final preferred480 = bestAtMost(mp4Sources, 520);

    final ordered = <VideoSource>[
      if (preferredHls != null) preferredHls,
      if (preferred720 != null) preferred720,
      if (preferred480 != null) preferred480,
      if (fallbackUrl.isNotEmpty) VideoSource(url: fallbackUrl),
    ];

    return _dedupe(ordered);
  }

  /// Supprime les doublons par URL (garde le premier rencontré)
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
