import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter/material.dart';

class VideoTools {
  /// Génère une miniature robuste à partir d'une vidéo
  static Future<File?> generateThumbnail(String inputPath) async {
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        print("Fichier vidéo introuvable: $inputPath");
        return null;
      }

      final thumbnailFile = await VideoCompress.getFileThumbnail(
        inputPath,
        quality: 50,
        position: 1000, // Position 1 seconde
      );

      if (thumbnailFile.path.isEmpty) return null;

      final thumb = File(thumbnailFile.path);

      // Essayer jusqu'à 3 secondes pour que le fichier apparaisse
      int retries = 10;
      while (!await thumb.exists() && retries > 0) {
        await Future.delayed(const Duration(milliseconds: 300));
        retries--;
      }

      return await thumb.exists() ? thumb : null;
    } catch (e) {
      print('Erreur thumbnail: $e');
      return null;
    }
  }

  /// Miniature de secours (image noire PNG)
  static Future<File> generateFallbackThumbnail() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = Colors.black;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 128, 128), paint);
    final picture = recorder.endRecording();
    final img = await picture.toImage(128, 128);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/fallback_thumbnail.png');
    await file.writeAsBytes(byteData!.buffer.asUint8List());
    return file;
  }

  /// Compresse la vidéo en qualité moyenne ou basse si nécessaire
  static Future<File?> compressVideoSilently(String inputPath) async {
    try {
      final result = await _attemptCompression(inputPath, VideoQuality.MediumQuality);
      if (result != null) return result;

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
      // Optionnel : log progression
    });

    final compressionFuture = VideoCompress.compressVideo(
      inputPath,
      quality: quality,
      deleteOrigin: false,
      includeAudio: true,
    );

    compressionFuture.timeout(
      const Duration(seconds: 120),
      onTimeout: () async {
        await VideoCompress.cancelCompression();
        subscription.unsubscribe();
        completer.complete(null);
        return null;
      },
    ).then((info) {
      subscription.unsubscribe();
      if (info != null && info.path != null && File(info.path!).existsSync()) {
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
    } catch (_) {}
  }

  /// Supprime tous les caches vidéo compressés
  static Future<void> dispose() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (_) {}
  }
}
