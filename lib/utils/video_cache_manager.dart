import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

class VideoCacheManager {
  static const key = 'videoCache';
  static VideoCacheManager? _instance;
  late final Future<BaseCacheManager> _cacheFuture;

  factory VideoCacheManager() {
    return _instance ??= VideoCacheManager._();
  }

  VideoCacheManager._() {
    _cacheFuture = _createCacheManager();
  }

  Future<BaseCacheManager> get manager async => await _cacheFuture;

  Future<BaseCacheManager> _createCacheManager() async {
    // Utilise un dossier persistant et non temporaire
    final cacheDir = await getApplicationSupportDirectory(); 
    final videoCacheDir = Directory('${cacheDir.path}/$key');

    if (!await videoCacheDir.exists()) {
      await videoCacheDir.create(recursive: true);
    }

    return CacheManager(
      Config(
        key,
        stalePeriod: const Duration(days: 30),
        maxNrOfCacheObjects: 50,
        repo: JsonCacheInfoRepository(databaseName: key),
        fileService: HttpFileService(),
        fileSystem: IOFileSystem(videoCacheDir.path),
      ),
    );
  }

  Future<FileInfo?> getFileFromCache(String url) async {
    final cache = await manager;
    try {
      final fileInfo = await cache.getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        return fileInfo;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<File?> downloadAndCacheFile(String url) async {
    final cache = await manager;
    try {
      final fileInfo = await cache.downloadFile(url);
      if (await fileInfo.file.exists()) {
        return fileInfo.file;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> preloadFile(String url) async {
    final cache = await manager;
    try {
      await cache.downloadFile(url);
    } catch (_) {}
  }

  Future<void> removeFile(String url) async {
    final cache = await manager;
    try {
      await cache.removeFile(url);
    } catch (_) {}
  }

  Future<void> emptyCache() async {
    final cache = await manager;
    try {
      await cache.emptyCache();
    } catch (_) {}
  }
}