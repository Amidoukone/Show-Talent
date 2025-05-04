import 'dart:async';
import 'dart:io';
import 'package:video_compress/video_compress.dart';

class VideoTools {
  /// Génère une miniature depuis un fichier vidéo
  static Future<File?> generateThumbnail(String inputPath) async {
    try {
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        inputPath,
        quality: 50,
        position: -1,
      );
      return File(thumbnailFile.path);
    } catch (e) {
      print('Erreur génération miniature : $e');
      return null;
    }
  }

  /// Compresse la vidéo en qualité moyenne ou basse si nécessaire
  static Future<File?> compressVideoSilently(String inputPath) async {
    try {
      final result = await _attemptCompression(inputPath, VideoQuality.MediumQuality);
      if (result != null) return result;

      // 🔁 Fallback vers qualité basse
      final fallbackResult = await _attemptCompression(inputPath, VideoQuality.LowQuality);
      return fallbackResult;
    } catch (e) {
      print('Erreur compression vidéo : $e');
      return null;
    }
  }

  /// Tente la compression vidéo avec une qualité donnée
  static Future<File?> _attemptCompression(String inputPath, VideoQuality quality) async {
    final completer = Completer<File?>();
    final subscription = VideoCompress.compressProgress$.subscribe((progress) {
      // Optionnel : logger ou afficher le progrès
    });

    final compressionFuture = VideoCompress.compressVideo(
      inputPath,
      quality: quality,
      deleteOrigin: false,
      includeAudio: true,
    );

    compressionFuture.timeout(
      const Duration(seconds: 90),
      onTimeout: () async {
        await VideoCompress.cancelCompression();
        subscription.unsubscribe();
        completer.complete(null);
        return null;
      },
    ).then((info) {
      subscription.unsubscribe();
      if (info != null && info.path != null) {
        completer.complete(File(info.path!));
      } else {
        completer.complete(null);
      }
    }).catchError((error) {
      subscription.unsubscribe();
      completer.complete(null);
    });

    return await completer.future;
  }

  /// Vérifie que la qualité de la vidéo respecte les dimensions minimales
  static Future<bool> isQualityAcceptable(String videoPath, {int minWidth = 480, int minHeight = 360}) async {
    try {
      final info = await VideoCompress.getMediaInfo(videoPath);
      if (info.width != null && info.height != null) {
        return info.width! >= minWidth && info.height! >= minHeight;
      }
      return true;
    } catch (e) {
      print('Erreur vérification qualité : $e');
      return true;
    }
  }

  /// Vérifie que la durée ne dépasse pas la limite
  static Future<bool> isDurationValid(String videoPath, {int maxDuration = 60}) async {
    try {
      final info = await VideoCompress.getMediaInfo(videoPath);
      if (info.duration != null) {
        final seconds = (info.duration! / 1000).round();
        return seconds <= maxDuration;
      }
      return true;
    } catch (e) {
      print('Erreur vérification durée : $e');
      return true;
    }
  }

  /// Annule toute compression en cours
  static Future<void> cancelCompression() async {
    try {
      await VideoCompress.cancelCompression();
    } catch (_) {
      // ignore
    }
  }

  /// Supprime tous les caches vidéo compressés
  static Future<void> dispose() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (_) {
      // ignore
    }
  }
}
