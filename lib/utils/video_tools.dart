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
/// - ✅ Génération de miniature fiable, avec retry et fallback (asset local).
/// - 🚫 Compression côté client retirée (la Cloud Function optimise).
/// - 📝 Logging (Firestore) pour diagnostiquer en prod.
/// ============================================================================
class VideoTools {
  static const String _logCollection = 'video_logs';
  static const String _fallbackAssetPath = 'assets/default_thumbnail.png';

  // Tolérance (en ms) pour absorber les imprécisions de métadonnées
  static const int _durationLeewayMs = 10000;

  // Petit délai après sélection (certains OS écrivent encore le fichier).
  static const Duration _settleDelay = Duration(milliseconds: 120);

  // Cache simple (chemin -> durée en ms) pour éviter de recalculer.
  static final Map<String, int> _durationCacheMs = {};

  // ---------------------------------------------------------------------------
  // MINIATURES
  // ---------------------------------------------------------------------------

  /// Génère une miniature depuis [inputPath].
  /// Retry automatique + fallback si échec.
  static Future<File?> generateThumbnail(String inputPath) async {
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        await _logInfo("generateThumbnail", "Input not found → fallback. path=$inputPath");
        return await generateFallbackThumbnail();
      }

      for (int attempt = 0; attempt < 3; attempt++) {
        final thumbFile = await VideoCompress.getFileThumbnail(
          inputPath,
          quality: 50,
          position: -1,
        );

        final file = File(thumbFile.path);
        if (await file.exists() && (await file.length()) > 0) {
          return file;
        }

        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }

      await _logInfo("generateThumbnail", "All attempts failed → fallback.");
      return await generateFallbackThumbnail();
    } catch (e) {
      await _logError("generateThumbnail", e.toString());
      return await generateFallbackThumbnail();
    }
  }

  /// Miniature de secours depuis un asset (PNG).
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

  /// Vérifie que la durée <= [maxDuration] secondes.
  static Future<bool> isDurationValid(String videoPath, {int maxDuration = 60}) async {
    try {
      final ms = await _getDurationMsRobust(videoPath);
      if (ms == null) {
        await _logInfo("isDurationValid", "Missing duration after probing.");
        return false;
      }

      final secondsFloor = (ms / 1000).floor();
      if (secondsFloor <= maxDuration) {
        return true;
      }

      final limitMs = maxDuration * 1000 + _durationLeewayMs;
      return ms <= limitMs;
    } catch (e) {
      await _logError("isDurationValid", e.toString());
      return false;
    }
  }

  static Future<int?> getDurationSeconds(String videoPath) async {
    try {
      final ms = await _getDurationMsRobust(videoPath);
      return ms != null ? (ms / 1000).floor() : null;
    } catch (e) {
      await _logError("getDurationSeconds", e.toString());
      return null;
    }
  }

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

  // --- Robust probing de la durée --------------------------------------------

  static Future<int?> _getDurationMsRobust(String videoPath) async {
    final cached = _durationCacheMs[videoPath];
    if (cached != null && cached > 0 && cached < 30 * 60 * 1000) return cached;

    await Future.delayed(_settleDelay);

    int? bestMs;

    Future<int?> probeOnce() async {
      final results = <int>[];

      final vpMs = await _probeDurationWithVideoPlayer(videoPath);
      if (vpMs != null) results.add(vpMs);

      final vcMs = await _probeDurationWithVideoCompress(videoPath);
      if (vcMs != null) results.add(vcMs);

      results.removeWhere((v) => v < 1000 || v > 30 * 60 * 1000);

      if (results.isEmpty) return null;
      results.sort();
      return results.first;
    }

    bestMs = await probeOnce();

    for (int attempt = 1; attempt <= 3; attempt++) {
      if (bestMs != null) break;
      await Future.delayed(Duration(milliseconds: 200 * attempt));
      try {
        await VideoCompress.deleteAllCache();
      } catch (_) {}
      bestMs = await probeOnce();
    }

    if (bestMs != null) {
      _durationCacheMs[videoPath] = bestMs;
    }

    return bestMs;
  }

  static Future<int?> _probeDurationWithVideoPlayer(String videoPath) async {
    VideoPlayerController? ctrl;
    try {
      final file = File(videoPath);
      if (!await file.exists()) return null;

      ctrl = VideoPlayerController.file(file);
      await ctrl.initialize().timeout(const Duration(seconds: 5));

      Duration d = ctrl.value.duration;

      if (d.inMilliseconds <= 0) {
        for (int i = 0; i < 5; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          d = ctrl.value.duration;
          if (d.inMilliseconds > 0) break;
        }
      }

      final ms = d.inMilliseconds;
      if (ms <= 1000 || ms > 30 * 60 * 1000) return null;

      return ms;
    } catch (_) {
      return null;
    } finally {
      await ctrl?.dispose();
    }
  }

  static Future<int?> _probeDurationWithVideoCompress(String videoPath) async {
    try {
      final info = await VideoCompress.getMediaInfo(videoPath);
      final num? raw = info.duration;
      if (raw == null) return null;

      final int intMs = raw.floor();
      if (intMs <= 1000 || intMs > 30 * 60 * 1000) return null;

      return intMs;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // NETTOYAGE
  // ---------------------------------------------------------------------------

  static Future<void> dispose() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (_) {}
  }

  static Future<void> purgeCacheForVideo(String path) async {
    try {
      _durationCacheMs.remove(path);
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
        'device': "${Platform.operatingSystem} ${Platform.version}",
        'hash': pathHash(message),
      });
    } catch (_) {}
  }

  static Future<void> _logInfo(String source, String message) async {
    try {
      await FirebaseFirestore.instance.collection(_logCollection).add({
        'timestamp': FieldValue.serverTimestamp(),
        'level': 'info',
        'source': source,
        'message': message,
        'device': "${Platform.operatingSystem} ${Platform.version}",
      });
    } catch (_) {}
  }

  static int pathHash(String path) => path.hashCode;

  // ---------------------------------------------------------------------------
  // AIDES
  // ---------------------------------------------------------------------------

  static String inferImageContentTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }
}
