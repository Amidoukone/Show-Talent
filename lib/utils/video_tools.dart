import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

class VideoTools {
  static const String _logCollection = 'video_logs';

  /// ✅ Génère une miniature robuste ou par défaut (image plus engageante)
  static Future<File?> generateThumbnail(String inputPath) async {
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        print("Fichier vidéo introuvable: $inputPath");
        return await generateFallbackThumbnail();
      }

      final thumbnailFile = await VideoCompress.getFileThumbnail(
        inputPath,
        quality: 50,
        position: -1,
      );

      if (thumbnailFile.path.isEmpty || !(await File(thumbnailFile.path).exists())) {
        print("Thumbnail path vide ou fichier inexistant.");
        return await generateFallbackThumbnail();
      }

      final thumb = File(thumbnailFile.path);
      int retries = 10;
      while (!await thumb.exists() && retries > 0) {
        await Future.delayed(const Duration(milliseconds: 300));
        retries--;
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

  /// ✅ Miniature par défaut engageante (icône vidéo)
  static Future<File> generateFallbackThumbnail() async {
    try {
      final byteData = await rootBundle.load('assets/default_thumbnail.png');
      final dir = await getTemporaryDirectory();
      final filename = 'fallback_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      print("Miniature par défaut générée.");
      return file;
    } catch (e) {
      await _logError("generateFallbackThumbnail", e.toString());
      rethrow;
    }
  }

  /// ✅ Compression toujours appliquée pour homogénéisation
  static Future<File?> compressVideoSilently(String inputPath) async {
    try {
      final compressedFile = await _attemptCompression(inputPath, VideoQuality.MediumQuality);
      if (compressedFile != null && await compressedFile.length() > 100 * 1024) {
        print("✅ Compression réussie : ${compressedFile.length()} octets");
        return compressedFile;
      }

      print("❌ Compression échouée ou fichier trop petit.");
      return File(inputPath);
    } catch (e) {
      await _logError("compressVideoSilently", e.toString());
      return null;
    }
  }

  /// ✅ Tentative de compression avec timeout contrôlé + fallback
  static Future<File?> _attemptCompression(String inputPath, VideoQuality quality) async {
    try {
      final info = await VideoCompress.compressVideo(
        inputPath,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
      ).timeout(
        const Duration(seconds: 120),
        onTimeout: () async {
          await VideoCompress.cancelCompression();
          print("⏱️ Compression annulée : trop longue (> 2 min).");
          await _logError("compression_timeout", "Compression > 2 minutes annulée.");
          return null;
        },
      );

      if (info != null && info.path != null) {
        final file = File(info.path!);
        if (await file.exists() && await file.length() > 0) {
          return file;
        }
      }

      return null;
    } catch (e) {
      await _logError("_attemptCompression", e.toString());
      return null;
    }
  }

  static Future<bool> isQualityAcceptable(String videoPath, {int minWidth = 480, int minHeight = 360}) async {
    try {
      final info = await VideoCompress.getMediaInfo(videoPath);
      if (info.width != null && info.height != null) {
        return info.width! >= minWidth && info.height! >= minHeight;
      }
      return false;
    } catch (e) {
      await _logError("isQualityAcceptable", e.toString());
      return false;
    }
  }

  static Future<bool> isDurationValid(String videoPath, {int maxDuration = 60}) async {
    try {
      final info = await VideoCompress.getMediaInfo(videoPath);
      if (info.duration != null) {
        final seconds = (info.duration! / 1000).round();
        return seconds <= maxDuration;
      }
      return false;
    } catch (e) {
      await _logError("isDurationValid", e.toString());
      return false;
    }
  }

  static Future<void> cancelCompression() async {
    try {
      await VideoCompress.cancelCompression();
    } catch (_) {}
  }

  static Future<void> dispose() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (_) {}
  }

  /// 🔍 Loggue les erreurs dans Firestore
  static Future<void> _logError(String source, String message) async {
    try {
      await FirebaseFirestore.instance.collection(_logCollection).add({
        'timestamp': FieldValue.serverTimestamp(),
        'source': source,
        'message': message,
        'device': Platform.operatingSystem,
      });
    } catch (e) {
      print("Erreur lors du log Firestore: $e");
    }
  }
}
