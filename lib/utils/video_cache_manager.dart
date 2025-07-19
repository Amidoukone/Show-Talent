import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

class VideoCacheManager extends CacheManager {
  static const key = 'videoCache';
  static VideoCacheManager? _instance;
  static const int maxCacheSizeMB = 300;
  static const int purgeBlockSizeMB = 50;

  factory VideoCacheManager() {
    return _instance ??= VideoCacheManager._internal();
  }

  VideoCacheManager._internal()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 15),
            maxNrOfCacheObjects: 50,
            repo: JsonCacheInfoRepository(databaseName: key),
            fileService: HttpFileService(),
            fileSystem: IOFileSystem(Directory.systemTemp.path),
          ),
        );

  static Future<String> getCacheDirectoryPath() async {
    final supportDir = await getApplicationSupportDirectory();
    final videoCacheDir = Directory('${supportDir.path}/$key');
    if (!await videoCacheDir.exists()) {
      await videoCacheDir.create(recursive: true);
      debugPrint('[VideoCacheManager] Created directory at ${videoCacheDir.path}');
    }
    return videoCacheDir.path;
  }

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

  @override
  Future<FileInfo> downloadFile(
    String url, {
    Map<String, String>? authHeaders,
    bool force = false,
    String? key,
  }) async {
    final fileInfo = await super.downloadFile(url, authHeaders: authHeaders, force: force, key: key);
    debugPrint('[VideoCacheManager] Cached: $url');
    await _autoPurgeIfNeeded();
    return fileInfo;
  }

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

  Future<void> _autoPurgeIfNeeded() async {
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
    debugPrint('[VideoCacheManager] Cache size: $totalMB MB');

    if (totalMB <= maxCacheSizeMB) return;

    debugPrint('[VideoCacheManager] Purging cache...');

    final sortedFiles = fileData.entries.toList();
    sortedFiles.sort((a, b) {
      final aTime = a.key.statSync().accessed;
      final bTime = b.key.statSync().accessed;
      return aTime.compareTo(bTime);
    });

    int freed = 0;
    final toFreeBytes = purgeBlockSizeMB * 1024 * 1024;

    for (final entry in sortedFiles) {
      try {
        await entry.key.delete();
        freed += entry.value;
        if (freed >= toFreeBytes) break;
      } catch (_) {}
    }

    final freedMB = freed ~/ (1024 * 1024);
    debugPrint('[VideoCacheManager] Freed $freedMB MB from cache');
  }
}
