import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../services/client_logger.dart';

class PreparedVideoFile {
  const PreparedVideoFile({
    required this.file,
    required this.wasTrimmed,
    this.originalDurationSeconds,
    this.uploadDurationSeconds,
  });

  final File file;
  final bool wasTrimmed;
  final int? originalDurationSeconds;
  final int? uploadDurationSeconds;
}

class VideoPreparationException implements Exception {
  const VideoPreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// ============================================================================
/// VideoTools
/// ----------------------------------------------------------------------------
/// Utilitaires vidéo côté client:
/// - ✅ Validation robuste de la durée (<= 60s) : double sonde (VideoPlayer + VideoCompress),
///   sélection du MIN obtenu, re-sondage avec délais, tolérance ms.
/// - ✅ Génération de miniature fiable, avec retry et fallback (asset local).
/// - 🚫 Compression côté client retirée (la Cloud Function optimise).
/// - 📝 Logging centralisé via Cloud Function (ClientLogger).
/// ============================================================================
class VideoTools {
  static const String _fallbackAssetPath = 'assets/default_thumbnail.png';

  // Tolérance (en ms) pour absorber les imprécisions de métadonnées
  static const int _durationLeewayMs = 10000;
  static const int defaultMaxUploadDurationSeconds = 60;

  // Petit délai après sélection (certains OS écrivent encore le fichier).
  static const Duration _settleDelay = Duration(milliseconds: 120);
  static const Duration _playerProbeTimeout = Duration(seconds: 7);
  static const Duration _playerProbeRetryDelay = Duration(milliseconds: 200);

  // Cache simple (chemin -> durée en ms) pour éviter de recalculer.
  static final Map<String, int> _durationCacheMs = {};
  static final Map<String, (int, int)> _dimensionsCache = {};

  // ---------------------------------------------------------------------------
  // MINIATURES
  // ---------------------------------------------------------------------------

  /// Génère une miniature depuis [inputPath].
  /// Retry automatique + fallback si échec.
  static Future<File?> generateThumbnail(String inputPath) async {
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        await _logInfo(
          "generateThumbnail",
          "Input not found → fallback. path=$inputPath",
        );
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
      final file = File(
        '${dir.path}/fallback_${DateTime.now().millisecondsSinceEpoch}.png',
      );
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
      final dims = await _getDimensionsRobust(videoPath);
      final w = dims?.$1;
      final h = dims?.$2;

      if (w != null && h != null) {
        final ok = w >= minWidth && h >= minHeight;
        if (!ok) {
          await _logInfo(
            "isQualityAcceptable",
            "Too low: ${w}x$h (min ${minWidth}x$minHeight)",
          );
        }
        return ok;
      }

      // Métadonnées absentes → on n’empêche pas l’upload
      await _logInfo(
        "isQualityAcceptable",
        "Missing width/height after probes → allow upload.",
      );
      return true;
    } catch (e) {
      await _logError("isQualityAcceptable", e.toString());
      return false;
    }
  }

  /// Vérifie que la durée <= [maxDuration] secondes.
  static Future<bool> isDurationValid(
    String videoPath, {
    int maxDuration = 60,
  }) async {
    try {
      final ms = await _getDurationMsRobust(videoPath);
      if (ms == null) {
        await _logInfo(
          "isDurationValid",
          "Missing duration after probing → allow upload.",
        );
        return true;
      }

      final secondsFloor = (ms / 1000).floor();
      if (secondsFloor <= maxDuration) return true;

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

  static Future<PreparedVideoFile> prepareVideoFileForUpload(
    String videoPath, {
    int maxDurationSeconds = defaultMaxUploadDurationSeconds,
  }) async {
    final source = File(videoPath);
    if (!await source.exists()) {
      throw const VideoPreparationException('Vidéo introuvable.');
    }

    final sourceDurationMs = await _getDurationMsRobust(videoPath);
    if (sourceDurationMs == null ||
        _isWithinDurationLimit(sourceDurationMs, maxDurationSeconds)) {
      return PreparedVideoFile(
        file: source,
        wasTrimmed: false,
        originalDurationSeconds: _durationMsToSeconds(sourceDurationMs),
        uploadDurationSeconds: _durationMsToSeconds(sourceDurationMs),
      );
    }

    await _logInfo(
      'prepareVideoFileForUpload',
      'Trimming long video: ${_durationMsToSeconds(sourceDurationMs)}s '
          '-> ${maxDurationSeconds}s',
    );

    final trimmed = await _trimVideoToDuration(
      videoPath,
      maxDurationSeconds: maxDurationSeconds,
    );
    final trimmedDurationMs = await _getDurationMsRobust(trimmed.path);

    if (trimmedDurationMs != null &&
        !_isWithinDurationLimit(trimmedDurationMs, maxDurationSeconds)) {
      throw VideoPreparationException(
        'La vidéo préparée dure ${_formatDurationSeconds(_durationMsToSeconds(trimmedDurationMs))}. '
        'La limite est de ${maxDurationSeconds}s.',
      );
    }

    return PreparedVideoFile(
      file: trimmed,
      wasTrimmed: true,
      originalDurationSeconds: _durationMsToSeconds(sourceDurationMs),
      uploadDurationSeconds:
          _durationMsToSeconds(trimmedDurationMs) ?? maxDurationSeconds,
    );
  }

  static Future<(int?, int?)> getDimensions(String videoPath) async {
    try {
      final dims = await _getDimensionsRobust(videoPath);
      return (dims?.$1, dims?.$2);
    } catch (e) {
      await _logError("getDimensions", e.toString());
      return (null, null);
    }
  }

  // ---------------------------------------------------------------------------
  // DURATION – ROBUST PROBING
  // ---------------------------------------------------------------------------

  static Future<int?> _getDurationMsRobust(String videoPath) async {
    final cached = _durationCacheMs[videoPath];
    if (cached != null && cached > 0 && cached < 30 * 60 * 1000) {
      return cached;
    }

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

    for (int attempt = 1; attempt <= 3 && bestMs == null; attempt++) {
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

  static bool _isWithinDurationLimit(int durationMs, int maxDurationSeconds) {
    final secondsFloor = (durationMs / 1000).floor();
    if (secondsFloor <= maxDurationSeconds) return true;

    final limitMs = maxDurationSeconds * 1000 + _durationLeewayMs;
    return durationMs <= limitMs;
  }

  static int? _durationMsToSeconds(int? durationMs) {
    return durationMs != null ? (durationMs / 1000).floor() : null;
  }

  static String _formatDurationSeconds(int? seconds) {
    if (seconds == null) return 'inconnue';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes}m ${remainingSeconds.toString().padLeft(2, '0')}s';
  }

  static Future<File> _trimVideoToDuration(
    String videoPath, {
    required int maxDurationSeconds,
  }) async {
    try {
      final info = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality.DefaultQuality,
        deleteOrigin: false,
        startTime: 0,
        duration: maxDurationSeconds,
        includeAudio: true,
        frameRate: 30,
      );

      final outputPath = info?.path;
      if (info == null ||
          info.isCancel == true ||
          outputPath == null ||
          outputPath.trim().isEmpty) {
        throw const VideoPreparationException(
          'Préparation vidéo annulée ou incomplète.',
        );
      }

      final file = File(outputPath);
      if (!await file.exists() || await file.length() <= 0) {
        throw const VideoPreparationException(
          'Fichier vidéo préparé introuvable.',
        );
      }

      return file;
    } catch (error) {
      if (error is VideoPreparationException) {
        rethrow;
      }
      await _logError('_trimVideoToDuration', error.toString());
      throw const VideoPreparationException(
        'Impossible de préparer un extrait de 60 secondes.',
      );
    }
  }

  static Future<int?> _probeDurationWithVideoPlayer(String videoPath) async {
    VideoPlayerController? ctrl;
    try {
      final file = File(videoPath);
      if (!await file.exists()) return null;

      ctrl = VideoPlayerController.file(file);
      await ctrl.initialize().timeout(_playerProbeTimeout);

      Duration d = ctrl.value.duration;
      if (d.inMilliseconds <= 0) {
        for (int i = 0; i < 5; i++) {
          await Future.delayed(_playerProbeRetryDelay);
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
  // DIMENSIONS – ROBUST PROBING
  // ---------------------------------------------------------------------------

  static Future<(int, int)?> _getDimensionsRobust(String videoPath) async {
    final cached = _dimensionsCache[videoPath];
    if (cached != null) return cached;

    await Future.delayed(_settleDelay);

    (int, int)? playerDimensions;
    (int, int)? compressDimensions;

    (int, int)? normalizeDimensions(int? w, int? h) {
      if (w == null || h == null || w <= 0 || h <= 0) {
        return null;
      }
      return (w, h);
    }

    Future<void> probeWithVideoPlayer() async {
      VideoPlayerController? ctrl;
      try {
        final file = File(videoPath);
        if (!await file.exists()) return;

        ctrl = VideoPlayerController.file(file);
        await ctrl.initialize().timeout(_playerProbeTimeout);

        var size = ctrl.value.size;
        if (size.width <= 0 || size.height <= 0) {
          for (int i = 0; i < 4; i++) {
            await Future.delayed(_playerProbeRetryDelay);
            size = ctrl.value.size;
            if (size.width > 0 && size.height > 0) break;
          }
        }

        playerDimensions = normalizeDimensions(
          size.width.round(),
          size.height.round(),
        );
      } catch (_) {
      } finally {
        await ctrl?.dispose();
      }
    }

    Future<void> probeWithVideoCompress() async {
      try {
        final info = await VideoCompress.getMediaInfo(videoPath);
        compressDimensions = normalizeDimensions(
          (info.width is num) ? (info.width as num).round() : null,
          (info.height is num) ? (info.height as num).round() : null,
        );
      } catch (_) {}
    }

    await probeWithVideoCompress();
    await probeWithVideoPlayer();

    if (playerDimensions == null && compressDimensions == null) {
      try {
        await VideoCompress.deleteAllCache();
      } catch (_) {}
      await Future.delayed(_playerProbeRetryDelay * 2);
      await probeWithVideoCompress();
      await probeWithVideoPlayer();
    }

    final preferred = playerDimensions ?? compressDimensions;
    if (preferred != null) {
      final tuple = preferred;
      _dimensionsCache[videoPath] = tuple;
      return tuple;
    }

    return null;
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
      _dimensionsCache.remove(path);
      await VideoCompress.deleteAllCache();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // LOGGING (CLOUD)
  // ---------------------------------------------------------------------------

  static Future<void> _logError(String source, String message) async {
    try {
      await ClientLogger.instance.logError(
        source,
        message,
        metadata: {
          'device': "${Platform.operatingSystem} ${Platform.version}",
          'hash': pathHash(message),
        },
      );
    } catch (_) {}
  }

  static Future<void> _logInfo(String source, String message) async {
    try {
      await ClientLogger.instance.logInfo(
        source,
        message,
        metadata: {
          'device': "${Platform.operatingSystem} ${Platform.version}",
        },
      );
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
