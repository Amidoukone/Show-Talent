import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

/// ============================================================================
/// VideoTools
/// ----------------------------------------------------------------------------
/// Utilitaires vidéo côté client:
/// - ✅ Validation robuste de la durée (<= 60s) : double sonde (VideoPlayer + VideoCompress),
///   sélection du MIN obtenu, re-sondage avec délais, tolérance ms.
/// - ✅ Génération de miniature fiable, avec fallback (asset local) si échec.
/// - 🚫 Compression côté client retirée (la Cloud Function optimise).
/// - 📝 Logging (Firestore) pour diagnostiquer en prod.
/// ============================================================================
class VideoTools {
  static const String _logCollection = 'video_logs';
  static const String _fallbackAssetPath = 'assets/default_thumbnail.png';

  // Tolérance pour absorber les imprécisions de métadonnées (VFR, conteneur, etc.)
  // Correction : Augmentée à 10 secondes (10000 ms)
  static const int _durationLeewayMs = 10000;

  // Petit délai de stabilisation après sélection (certains OS écrivent encore le fichier).
  static const Duration _settleDelay = Duration(milliseconds: 120);

  // Cache simple (chemin -> durée en ms) pour éviter de recalculer.
  static final Map<String, int> _durationCacheMs = {};

  // ---------------------------------------------------------------------------
  // MINIATURES
  // ---------------------------------------------------------------------------

  /// Génère une miniature depuis [inputPath] via VideoCompress.
  /// Renvoie un [File] pointant vers l’image ou une miniature de fallback.
  static Future<File?> generateThumbnail(String inputPath) async {
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        await _logInfo("generateThumbnail", "Input not found → fallback. path=$inputPath");
        return await generateFallbackThumbnail();
      }

      final thumbnailFile = await VideoCompress.getFileThumbnail(
        inputPath,
        quality: 50, // compromis lisibilité/poids
        position: -1,
      );

      if (thumbnailFile.path.isEmpty || !(await File(thumbnailFile.path).exists())) {
        await _logInfo("generateThumbnail", "Generated file missing → fallback.");
        return await generateFallbackThumbnail();
      }

      final thumb = File(thumbnailFile.path);
      // Certains devices ont un petit délai I/O
      for (int i = 0; i < 10; i++) {
        if (await thumb.exists()) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (await thumb.exists() && (await thumb.length()) > 0) {
        return thumb;
      }

      return await generateFallbackThumbnail();
    } catch (e) {
      await _logError("generateThumbnail", e.toString());
      return await generateFallbackThumbnail();
    }
  }

  /// Génère une miniature de secours depuis un asset (PNG).
  /// Conseillé: lors de l’upload, déclarer contentType=image/png.
  static Future<File> generateFallbackThumbnail() async {
    try {
      final byteData = await rootBundle.load(_fallbackAssetPath);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fallback_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return file;
    } catch (e) {
      await _logError("generateFallbackThumbnail", e.toString());
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // VALIDATIONS
  // ---------------------------------------------------------------------------

  /// Vérifie une qualité minimale (par défaut 480x360).
  static Future<bool> isQualityAcceptable(
    String videoPath, {
    int minWidth = 480,
    int minHeight = 360,
  }) async {
    try {
      final info = await VideoCompress.getMediaInfo(videoPath);
      final int? w = (info.width is num) ? (info.width as num).round() : null;
      final int? h = (info.height is num) ? (info.height as num).round() : null;

      if (w != null && h != null) {
        final ok = w >= minWidth && h >= minHeight;
        if (!ok) {
          await _logInfo("isQualityAcceptable", "Too low: ${w}x$h (min ${minWidth}x$minHeight)");
        }
        return ok;
      }
      await _logInfo("isQualityAcceptable", "Missing width/height.");
      return false;
    } catch (e) {
      await _logError("isQualityAcceptable", e.toString());
      return false;
    }
  }

  /// ✅ Vérifie que la durée <= [maxDuration] secondes (ultra-robuste).
  ///
  /// Stratégie :
  ///  1) Petit délai de stabilisation (_settleDelay)
  ///  2) Double sonde :
  ///     - (A) VideoPlayerController (AVPlayer/ExoPlayer) → très fiable
  ///     - (B) VideoCompress.getMediaInfo
  ///     On prend **le MIN** des durées > 0 obtenues, pour éliminer les sur-rapports sporadiques.
  ///  3) Si besoin, re-sondage (4 tentatives) avec délais croissants et purge du cache VideoCompress.
  ///  4) Application d’une marge de tolérance (_durationLeewayMs).
  static Future<bool> isDurationValid(String videoPath, {int maxDuration = 60}) async {
    try {
      final ms = await _getDurationMsRobust(videoPath);
      if (ms == null) {
        await _logInfo("isDurationValid", "Missing duration after robust probing.");
        return false;
      }

      final secondsFloor = (ms / 1000).floor();
      await _logInfo("isDurationValid", "Computed duration: ${ms}ms (${secondsFloor}s), maxDuration=$maxDuration");

      if (secondsFloor <= maxDuration) {
        await _logInfo("isDurationValid", "OK floor=$secondsFloor ≤ $maxDuration (ms=$ms)");
        return true;
      }

      // Marge de tolérance (ex: 60050ms accepté pour max=60000ms)
      final limitMs = maxDuration * 1000 + _durationLeewayMs;
      if (ms <= limitMs) {
        await _logInfo(
          "isDurationValid",
          "Accepted by leeway: ms=$ms ≤ limit=$limitMs (max=${maxDuration * 1000}+$_durationLeewayMs)",
        );
        return true;
      }

      await _logInfo("isDurationValid", "Rejected: ms=$ms > limit=$limitMs");
      return false;
    } catch (e) {
      await _logError("isDurationValid", e.toString());
      return false;
    }
  }

  /// Renvoie la durée (floor, en secondes) ou null si inconnue.
  static Future<int?> getDurationSeconds(String videoPath) async {
    try {
      final ms = await _getDurationMsRobust(videoPath);
      return ms != null ? (ms / 1000).floor() : null;
    } catch (e) {
      await _logError("getDurationSeconds", e.toString());
      return null;
    }
  }

  /// Renvoie (width,height) si disponibles (coercition sûre vers int).
  static Future<(int?, int?)> getDimensions(String videoPath) async {
    try {
      final info = await VideoCompress.getMediaInfo(videoPath);
      final int? w = (info.width is num) ? (info.width as num).round() : null;
      final int? h = (info.height is num) ? (info.height as num).round() : null;
      return (w, h);
    } catch (e) {
      await _logError("getDimensions", e.toString());
      return (null, null);
    }
  }

  // --- Robust probing de la durée : double sonde + retries -------------------

  static Future<int?> _getDurationMsRobust(String videoPath) async {
    // 0) Cache immédiat
    final cached = _durationCacheMs[videoPath];
    if (cached != null && cached > 0 && cached < 30 * 60 * 1000) return cached;

    // 1) Laisser l’OS “finir” la copie du fichier (ImagePicker)
    await Future.delayed(_settleDelay);

    int? bestMs;

    // Effectue une double sonde et retourne le MIN des valeurs positives et raisonnables
    Future<int?> probeOnce() async {
      final results = <int>[];

      final vpMs = await _probeDurationWithVideoPlayer(videoPath);
      if (vpMs != null && vpMs > 0 && vpMs < 30 * 60 * 1000) results.add(vpMs);

      final vcMs = await _probeDurationWithVideoCompress(videoPath);
      if (vcMs != null && vcMs > 0 && vcMs < 30 * 60 * 1000) results.add(vcMs);

      // Filtrer les durées vraiment aberrantes (<1s ou >30min)
      results.removeWhere((v) => v < 1000);

      if (results.isEmpty) return null;
      results.sort();
      await _logInfo("_getDurationMsRobust", "Probed durations: $results");
      return results.first; // MIN
    }

    // 2) 1ère sonde
    bestMs = await probeOnce();

    // 3) Si échec ou valeur suspecte, on re-sonde jusqu’à 4 fois
    for (int attempt = 1; attempt <= 4; attempt++) {
      if (bestMs != null && bestMs > 0 && bestMs < 30 * 60 * 1000) break;

      // délais croissants
      await Future.delayed(Duration(milliseconds: 200 * attempt));

      // purge caches VideoCompress (évite réutilisation de metadata approximatives)
      try {
        await VideoCompress.deleteAllCache();
      } catch (_) {}

      final retryMs = await probeOnce();
      if (retryMs != null && retryMs > 0 && retryMs < 30 * 60 * 1000) {
        bestMs = (bestMs == null) ? retryMs : (retryMs < bestMs ? retryMs : bestMs);
      }
    }

    if (bestMs != null && bestMs > 0 && bestMs < 30 * 60 * 1000) {
      _durationCacheMs[videoPath] = bestMs;
    }

    await _logInfo("_getDurationMsRobust", "Final duration: $bestMs ms for $videoPath");
    return bestMs;
  }

  /// Sonde la durée via VideoPlayerController (ExoPlayer/AVPlayer) — très fiable.
  static Future<int?> _probeDurationWithVideoPlayer(String videoPath) async {
    VideoPlayerController? ctrl;
    try {
      final file = File(videoPath);
      if (!await file.exists()) {
        await _logInfo("_probeDurationWithVideoPlayer", "file not found");
        return null;
      }

      ctrl = VideoPlayerController.file(file);

      // initialize avec timeout
      await ctrl.initialize().timeout(const Duration(seconds: 5));

      // Sur certains médias, la durée peut être nulle pendant quelques ms
      Duration d = ctrl.value.duration;

      if (d.inMilliseconds <= 0) {
        for (int i = 0; i < 8; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          d = ctrl.value.duration;
          if (d.inMilliseconds > 0) break;
        }
      }

      final ms = d.inMilliseconds;

      // Sanity check : si vraiment énorme ou trop petite (<1s), on ignore
      if (ms <= 0 || ms > 30 * 60 * 1000 || ms < 1000) {
        await _logInfo("_probeDurationWithVideoPlayer", "ms=$ms ignored");
        return null;
      }

      await _logInfo("_probeDurationWithVideoPlayer", "ms=$ms");
      return ms;
    } catch (e) {
      await _logInfo("_probeDurationWithVideoPlayer_error", e.toString());
      return null;
    } finally {
      try {
        await ctrl?.dispose();
      } catch (_) {}
    }
  }

  /// Sonde la durée via VideoCompress.getMediaInfo (pratique et rapide).
  static Future<int?> _probeDurationWithVideoCompress(String videoPath) async {
    try {
      final info = await VideoCompress.getMediaInfo(videoPath);
      final num? raw = info.duration; // ms sous forme num (double/int selon version)
      if (raw == null || raw <= 0) return null;

      final int intMs = raw.floor();

      // Sanity check similaire
      if (intMs <= 0 || intMs > 30 * 60 * 1000 || intMs < 1000) {
        await _logInfo("_probeDurationWithVideoCompress", "ms=$intMs ignored");
        return null;
      }

      await _logInfo("_probeDurationWithVideoCompress", "ms=$intMs");
      return intMs;
    } catch (e) {
      await _logInfo("_probeDurationWithVideoCompress_error", e.toString());
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ANNULATION / NETTOYAGE
  // ---------------------------------------------------------------------------

  static Future<void> dispose() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // LOGGING
  // ---------------------------------------------------------------------------

  static Future<void> _logError(String source, String message) async {
    try {
      await FirebaseFirestore.instance.collection(_logCollection).add({
        'timestamp': FieldValue.serverTimestamp(),
        'level': 'error',
        'source': source,
        'message': message,
        'device': Platform.operatingSystem,
      });
    } catch (e) {
      print("Log Firestore (error) failed: $e");
    }
  }

  static Future<void> _logInfo(String source, String message) async {
    try {
      await FirebaseFirestore.instance.collection(_logCollection).add({
        'timestamp': FieldValue.serverTimestamp(),
        'level': 'info',
        'source': source,
        'message': message,
        'device': Platform.operatingSystem,
      });
    } catch (e) {
      print("Log Firestore (info) failed: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // AIDES OPTIONNELLES (non bloquantes, utiles côté upload)
  // ---------------------------------------------------------------------------

  /// Déduit un content-type simple depuis l’extension du chemin.
  /// (Utile pour déclarer image/png sur le fallback, image/jpeg sur .jpg/.jpeg)
  static String inferImageContentTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg'; // défaut raisonnable
  }
}