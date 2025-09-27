// ignore_for_file: invalid_return_type_for_catch_error

import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

class VideoCacheManager extends CacheManager {
  static const key = 'videoCache';
  static VideoCacheManager? _instance;

  /// Limite max du cache en Mo
  static const int maxCacheSizeMB = 300;

  /// Taille minimale à libérer lors d’un purge (Mo)
  static const int purgeBlockSizeMB = 50;

  /// Empêche les purges concurrentes
  static bool _purgeLock = false;

  factory VideoCacheManager() {
    return _instance ??= VideoCacheManager._internal();
  }

  VideoCacheManager._internal()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 15),
            maxNrOfCacheObjects: 100, // on augmente légèrement
            repo: JsonCacheInfoRepository(databaseName: key),
            fileService: HttpFileService(),
            fileSystem: IOFileSystem(Directory.systemTemp.path),
          ),
        );

  /// 🔧 Retourne un chemin de cache dédié aux vidéos
  static Future<String> getCacheDirectoryPath() async {
    final supportDir = await getApplicationSupportDirectory();
    final videoCacheDir = Directory('${supportDir.path}/$key');

    if (!await videoCacheDir.exists()) {
      await videoCacheDir.create(recursive: true);
      debugPrint('[VideoCacheManager] Created directory at ${videoCacheDir.path}');
    }
    return videoCacheDir.path;
  }

  /// Singleton avec chemin correct
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
            maxNrOfCacheObjects: 100,
            repo: JsonCacheInfoRepository(databaseName: key),
            fileService: HttpFileService(),
            fileSystem: IOFileSystem(path),
          ),
        );

  /// 🔧 Télécharge et met en cache le fichier
  @override
  Future<FileInfo> downloadFile(
    String url, {
    Map<String, String>? authHeaders,
    bool force = false,
    String? key,
  }) async {
    final fileInfo = await super.downloadFile(url, authHeaders: authHeaders, force: force, key: key);
    debugPrint('[VideoCacheManager] Cached: $url');
    unawaited(_autoPurgeIfNeeded());
    return fileInfo;
  }

  /// Vérifie si une vidéo est déjà en cache
  static Future<File?> getFileIfCached(String url) async {
    try {
      final manager = await getInstance();
      final fileInfo = await manager.getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        debugPrint('[VideoCacheManager] File found in cache: $url');
        return fileInfo.file;
      }
    } catch (e) {
      debugPrint('[VideoCacheManager] getFileIfCached error: $e');
    }
    return null;
  }

  /// Taille actuelle du cache
  static Future<int> getCacheSizeInMB() async {
    try {
      final path = await getCacheDirectoryPath();
      final dir = Directory(path);
      if (!await dir.exists()) return 0;

      int total = 0;
      await for (var f in dir.list(recursive: true)) {
        if (f is File) total += await f.length();
      }
      final sizeMB = total ~/ (1024 * 1024);
      debugPrint('[VideoCacheManager] Cache size: $sizeMB MB');
      return sizeMB;
    } catch (e) {
      debugPrint('[VideoCacheManager] getCacheSizeInMB error: $e');
      return 0;
    }
  }

  /// 🔧 Purge automatique si la taille dépasse la limite
  Future<void> _autoPurgeIfNeeded() async {
    if (_purgeLock) return; // évite purges concurrentes
    _purgeLock = true;

    try {
      final cacheDirPath = await getCacheDirectoryPath();
      final dir = Directory(cacheDirPath);
      if (!await dir.exists()) return;

      final files = <File>[];
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) files.add(entity);
      }

      final fileData = <File, int>{};
      int totalSize = 0;
      for (final file in files) {
        try {
          final size = await file.length();
          fileData[file] = size;
          totalSize += size;
        } catch (_) {}
      }

      final totalMB = totalSize ~/ (1024 * 1024);
      debugPrint('[VideoCacheManager] Cache size before purge: $totalMB MB');

      if (totalMB <= maxCacheSizeMB) return;

      debugPrint('[VideoCacheManager] Purging cache...');
      final sorted = fileData.entries.toList()
        ..sort((a, b) {
          final aTime = _safeModifiedTime(a.key);
          final bTime = _safeModifiedTime(b.key);
          return aTime.compareTo(bTime); // plus ancien d’abord
        });

      int freed = 0;
      final toFreeBytes = purgeBlockSizeMB * 1024 * 1024;
      for (final e in sorted) {
        try {
          await e.key.delete().catchError((_) => null);
          freed += e.value;
          if (freed >= toFreeBytes) break;
        } catch (_) {}
      }

      final freedMB = freed ~/ (1024 * 1024);
      debugPrint('[VideoCacheManager] Freed $freedMB MB from cache');
    } finally {
      _purgeLock = false;
    }
  }

  /// 🔧 Récupère la date de dernière modif en toute sécurité
  DateTime _safeModifiedTime(File f) {
    try {
      return f.statSync().modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}
