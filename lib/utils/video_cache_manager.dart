// ignore_for_file: invalid_return_type_for_catch_error

import 'dart:io';
import 'dart:async';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:adfoot/services/app_logger.dart';

/// Le seul propriétaire du cache vidéo sur disque.
///
/// L'application a longtemps eu *deux* caches vidéo qui s'ignoraient :
/// celui-ci, rempli par les préchargements, et celui que
/// `cached_video_player_plus` ouvre tout seul dès qu'on lui donne une URL
/// réseau (`libCachedVideoPlayerPlusData`, dans le dossier cache de l'OS).
/// Chaque vidéo lue en streaming était donc téléchargée intégralement une
/// seconde fois, dans un dossier que cette classe ne purgeait jamais — d'où
/// un stockage qui grimpait bien au-delà de la limite annoncée, et surtout
/// une lecture qui se mettait en pause en boucle parce que le lecteur se
/// faisait voler sa bande passante par le téléchargement de ses propres
/// octets.
///
/// VideoManager passe désormais `skipCache: true` sur la branche streaming :
/// le lecteur ne télécharge plus rien derrière notre dos, et ce cache-ci est
/// le seul qui existe. [performStartupMaintenance] efface l'ancien.
class VideoCacheManager extends CacheManager {
  static const key = 'videoCache';

  /// Ancien dossier de blobs (`getApplicationSupportDirectory()/videoCache`).
  ///
  /// Il comptait comme « données utilisateur » sous Android : invisible pour
  /// le bouton « Vider le cache », jamais récupérable par le système sous
  /// pression de stockage. Les blobs vivent maintenant dans le dossier cache
  /// de l'OS, là où un cache doit être.
  static const String _legacySupportDirName = key;

  /// Cache interne de `cached_video_player_plus`, désormais orphelin.
  static const String _legacyPackageCacheDirName =
      'libCachedVideoPlayerPlusData';

  /// Plafond du cache en Mo : au-delà, on purge.
  static const int maxCacheSizeMB = 600;

  /// Cible visée par une purge, en Mo.
  ///
  /// Purger jusqu'à une cible plutôt que de libérer un bloc fixe évite de
  /// repurger à chaque téléchargement une fois le plafond atteint :
  /// l'ancienne version libérait 50 Mo puis se retrouvait à nouveau au
  /// plafond deux vidéos plus loin.
  static const int targetCacheSizeMB = 420;

  /// Nombre max d'entrées suivies par flutter_cache_manager.
  static const int maxCacheObjects = 150;

  /// Durée de vie d'une entrée non revue.
  static const Duration stalePeriod = Duration(days: 15);

  /// Une purge ne touche jamais un fichier utilisé aussi récemment.
  ///
  /// La vidéo en cours de lecture et ses voisines préchargées sont, par
  /// construction, les plus récemment utilisées ; ce délai les met hors
  /// d'atteinte sans que la purge ait besoin de connaître le lecteur.
  static const Duration _recentUseGracePeriod = Duration(minutes: 3);

  static const int _bytesPerMB = 1024 * 1024;

  static VideoCacheManager? _instance;
  static Future<VideoCacheManager>? _instanceFuture;
  static String? _cacheDirectoryPath;

  /// Empêche les purges concurrentes
  static bool _purgeLock = false;

  /// 🔧 Retourne le chemin du dossier de blobs vidéo.
  ///
  /// Doit rester cohérent avec le `IOFileSystem(key)` de la config :
  /// celui-ci joint toujours sa clé au dossier temporaire de l'OS.
  static Future<String> getCacheDirectoryPath() async {
    final cached = _cacheDirectoryPath;
    if (cached != null) return cached;

    final baseDir = await getTemporaryDirectory();
    final videoCacheDir = Directory(p.join(baseDir.path, key));

    if (!await videoCacheDir.exists()) {
      await videoCacheDir.create(recursive: true);
      AppLogger.debug(
          '[VideoCacheManager] Created directory at ${videoCacheDir.path}');
    }
    _cacheDirectoryPath = videoCacheDir.path;
    return videoCacheDir.path;
  }

  /// Singleton. Une seule construction, même sous appels concurrents.
  static Future<VideoCacheManager> getInstance() {
    final ready = _instance;
    if (ready != null) return Future.value(ready);
    return _instanceFuture ??= _createInstance();
  }

  static Future<VideoCacheManager> _createInstance() async {
    // Garantit que le dossier existe avant le premier accès disque.
    await getCacheDirectoryPath();
    final created = VideoCacheManager._internal();
    _instance = created;
    _instanceFuture = null;
    return created;
  }

  VideoCacheManager._internal()
      : super(
          Config(
            key,
            stalePeriod: stalePeriod,
            maxNrOfCacheObjects: maxCacheObjects,
            repo: JsonCacheInfoRepository(databaseName: key),
            fileService: HttpFileService(),
            // IOFileSystem attend une *clé* de dossier, pas un chemin : il la
            // joint lui-même au dossier temporaire de l'OS.
            fileSystem: IOFileSystem(key),
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
    final fileInfo = await super
        .downloadFile(url, authHeaders: authHeaders, force: force, key: key);
    AppLogger.debug('[VideoCacheManager] Cached: $url');
    unawaited(purgeIfNeeded());
    return fileInfo;
  }

  /// Vérifie si une vidéo est déjà en cache
  static Future<File?> getFileIfCached(String url) async {
    try {
      final manager = await getInstance();
      final fileInfo = await manager.getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        AppLogger.debug('[VideoCacheManager] File found in cache: $url');
        unawaited(_markUsed(fileInfo.file));
        return fileInfo.file;
      }
    } catch (e) {
      AppLogger.debug('[VideoCacheManager] getFileIfCached error: $e');
    }
    return null;
  }

  /// Supprime explicitement un artefact de cache pour une URL donnée.
  static Future<void> removeCachedFile(String url) async {
    try {
      final manager = await getInstance();
      await manager.removeFile(url);
      AppLogger.debug('[VideoCacheManager] Removed cached file: $url');
    } catch (e) {
      AppLogger.debug('[VideoCacheManager] removeCachedFile error: $e');
    }
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
      final sizeMB = total ~/ _bytesPerMB;
      AppLogger.debug('[VideoCacheManager] Cache size: $sizeMB MB');
      return sizeMB;
    } catch (e) {
      AppLogger.debug('[VideoCacheManager] getCacheSizeInMB error: $e');
      return 0;
    }
  }

  /// Ménage au démarrage : récupère l'espace des caches abandonnés, puis
  /// ramène le cache courant sous son plafond.
  ///
  /// Best-effort de bout en bout : c'est du disque, jamais un prérequis de
  /// démarrage. Appelé sans `await` depuis AppBootstrap.
  static Future<void> performStartupMaintenance() async {
    await _deleteLegacyCacheDirectories();
    await purgeIfNeeded();
  }

  static Future<void> _deleteLegacyCacheDirectories() async {
    final currentPath = await getCacheDirectoryPath();

    Future<void> deleteIfObsolete(Directory dir) async {
      try {
        if (p.equals(dir.path, currentPath)) return;
        if (!await dir.exists()) return;
        final freedMB = await _directorySizeMB(dir);
        await dir.delete(recursive: true);
        AppLogger.debug(
          '[VideoCacheManager] Reclaimed $freedMB MB from ${dir.path}',
        );
      } catch (e) {
        AppLogger.debug('[VideoCacheManager] Legacy cleanup skipped: $e');
      }
    }

    try {
      final supportDir = await getApplicationSupportDirectory();
      await deleteIfObsolete(
        Directory(p.join(supportDir.path, _legacySupportDirName)),
      );
    } catch (e) {
      AppLogger.debug('[VideoCacheManager] Support dir unavailable: $e');
    }

    try {
      final tempDir = await getTemporaryDirectory();
      await deleteIfObsolete(
        Directory(p.join(tempDir.path, _legacyPackageCacheDirName)),
      );
    } catch (e) {
      AppLogger.debug('[VideoCacheManager] Temp dir unavailable: $e');
    }
  }

  static Future<int> _directorySizeMB(Directory dir) async {
    int total = 0;
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total ~/ _bytesPerMB;
  }

  /// 🔧 Purge automatique si la taille dépasse la limite.
  ///
  /// Supprime du plus anciennement utilisé au plus récent, jusqu'à
  /// [targetCacheSizeMB]. Les fichiers utilisés dans les dernières minutes
  /// sont épargnés : c'est la vidéo à l'écran et ses voisines.
  static Future<void> purgeIfNeeded({bool force = false}) async {
    if (_purgeLock) return; // évite purges concurrentes
    _purgeLock = true;

    try {
      final cacheDirPath = await getCacheDirectoryPath();
      final dir = Directory(cacheDirPath);
      if (!await dir.exists()) return;

      final entries = <_CachedBlob>[];
      int totalSize = 0;
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          entries.add(_CachedBlob(entity, stat.size, _lastUsedAt(stat)));
          totalSize += stat.size;
        } catch (_) {}
      }

      final totalMB = totalSize ~/ _bytesPerMB;
      AppLogger.debug(
          '[VideoCacheManager] Cache size before purge: $totalMB MB');

      if (!force && totalMB <= maxCacheSizeMB) return;

      AppLogger.debug('[VideoCacheManager] Purging cache...');
      entries.sort((a, b) => a.lastUsedAt.compareTo(b.lastUsedAt));

      final protectedAfter = DateTime.now().subtract(_recentUseGracePeriod);
      final targetBytes = targetCacheSizeMB * _bytesPerMB;
      var remaining = totalSize;
      var freed = 0;

      for (final entry in entries) {
        if (remaining <= targetBytes) break;
        if (entry.lastUsedAt.isAfter(protectedAfter)) continue;
        try {
          await entry.file.delete();
          remaining -= entry.size;
          freed += entry.size;
        } catch (_) {}
      }

      final freedMB = freed ~/ _bytesPerMB;
      final remainingMB = remaining ~/ _bytesPerMB;
      AppLogger.debug(
        '[VideoCacheManager] Freed $freedMB MB from cache '
        '(now $remainingMB MB, target $targetCacheSizeMB MB)',
      );
    } catch (e) {
      AppLogger.debug('[VideoCacheManager] purgeIfNeeded error: $e');
    } finally {
      _purgeLock = false;
    }
  }

  /// Marque un fichier comme utilisé pour que la purge soit un vrai LRU.
  ///
  /// Sans ça, l'ordre de purge était l'ordre de *téléchargement* : une vidéo
  /// revue tous les jours se faisait supprimer avant une vidéo téléchargée
  /// plus tard et jamais relue.
  static Future<void> _markUsed(File file) async {
    final now = DateTime.now();
    try {
      await file.setLastAccessed(now);
    } catch (_) {
      // Certains systèmes de fichiers montés en noatime refusent atime.
      try {
        await file.setLastModified(now);
      } catch (_) {}
    }
  }

  static DateTime _lastUsedAt(FileStat stat) {
    final accessed = stat.accessed;
    final modified = stat.modified;
    return accessed.isAfter(modified) ? accessed : modified;
  }
}

class _CachedBlob {
  const _CachedBlob(this.file, this.size, this.lastUsedAt);

  final File file;
  final int size;
  final DateTime lastUsedAt;
}
