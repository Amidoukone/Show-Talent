import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

class VideoCacheManager extends CacheManager {
  static const key = 'videoCache';
  static VideoCacheManager? _instance;

  factory VideoCacheManager() {
    return _instance ??= VideoCacheManager._internal();
  }

  VideoCacheManager._internal()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 15), // ✅ 15 jours
            maxNrOfCacheObjects: 50,              // ✅ Limité à 50 vidéos
            repo: JsonCacheInfoRepository(databaseName: key),
            fileService: HttpFileService(),
            // 🔥 Placeholder temporaire, remplacé dynamiquement
            fileSystem: IOFileSystem(Directory.systemTemp.path),
          ),
        );

  /// ✅ Dossier de cache persistant (SupportDirectory), jamais vidé automatiquement
  static Future<String> getCacheDirectoryPath() async {
    final supportDir = await getApplicationSupportDirectory();
    final videoCacheDir = Directory('${supportDir.path}/$key');

    if (!await videoCacheDir.exists()) {
      await videoCacheDir.create(recursive: true);
      debugPrint('[VideoCacheManager] Created persistent cache directory at ${videoCacheDir.path}');
    }

    debugPrint('[VideoCacheManager] Using persistent cache directory: ${videoCacheDir.path}');
    return videoCacheDir.path;
  }

  /// ✅ Instanciation propre avec le bon chemin persistant
  static Future<VideoCacheManager> getInstance() async {
    if (_instance != null) return _instance!;

    final cachePath = await getCacheDirectoryPath();
    _instance = VideoCacheManager._withCustomPath(cachePath);
    return _instance!;
  }

  VideoCacheManager._withCustomPath(String path)
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 15),
            maxNrOfCacheObjects: 50,
            repo: JsonCacheInfoRepository(databaseName: key),
            fileService: HttpFileService(),
            fileSystem: IOFileSystem(path),
          ),
        );

  Future<FileInfo?> getFileIfCached(String url) async {
    try {
      final fileInfo = await getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        debugPrint('[VideoCacheManager] File found in cache: $url');
        return fileInfo;
      } else {
        debugPrint('[VideoCacheManager] File not found in cache: $url');
        return null;
      }
    } catch (e) {
      debugPrint('[VideoCacheManager] Error checking cache: $e');
      return null;
    }
  }

  @override
  Future<FileInfo> downloadFile(
    String url, {
    Map<String, String>? authHeaders,
    bool force = false,
    String? key,
  }) async {
    try {
      final fileInfo = await super.downloadFile(url, authHeaders: authHeaders, force: force, key: key);
      debugPrint('[VideoCacheManager] Downloaded and cached: $url');
      return fileInfo;
    } catch (e) {
      debugPrint('[VideoCacheManager] Error downloading: $e');
      rethrow;
    }
  }

  Future<File> downloadAndCache(String url) async {
    final fileInfo = await downloadFile(url);
    return fileInfo.file;
  }

  Future<void> clearCache() async {
    try {
      await emptyCache();
      debugPrint('[VideoCacheManager] Cache cleared');
    } catch (e) {
      debugPrint('[VideoCacheManager] Error clearing cache: $e');
    }
  }

  /// ✅ Option supplémentaire : surveillance manuelle de la taille totale
  Future<int> getCacheSizeInMB() async {
    try {
      final cacheDir = await getCacheDirectoryPath();
      final dir = Directory(cacheDir);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (var file in dir.list(recursive: true, followLinks: false)) {
        if (file is File) {
          totalSize += await file.length();
        }
      }
      return (totalSize / (1024 * 1024)).round();
    } catch (e) {
      debugPrint('[VideoCacheManager] Error calculating size: $e');
      return 0;
    }
  }
}
