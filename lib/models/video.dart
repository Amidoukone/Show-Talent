import 'package:cloud_firestore/cloud_firestore.dart';

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry),
    );
  }
  return null;
}

int? _asInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

List<VideoSource> _parseVideoSources(dynamic value) {
  if (value is! List) {
    return const <VideoSource>[];
  }

  return value
      .map(
        (entry) => VideoSource.fromMap(
          _asMap(entry) ?? const <String, dynamic>{},
        ),
      )
      .where((source) => source.url.isNotEmpty)
      .toList();
}

List<VideoSource> _dedupeVideoSources(Iterable<VideoSource> sources) {
  final seen = <String>{};
  final deduped = <VideoSource>[];

  for (final source in sources) {
    if (source.url.isEmpty) {
      continue;
    }
    if (seen.add(source.url)) {
      deduped.add(source);
    }
  }

  return deduped;
}

class VideoSource {
  final String url;
  final String? path;
  final String? quality;
  final String? type;
  final int? height;
  final int? bitrate;

  bool get isHls =>
      (type?.toLowerCase() == 'hls') || url.toLowerCase().contains('.m3u8');

  const VideoSource({
    required this.url,
    this.path,
    this.quality,
    this.type,
    this.height,
    this.bitrate,
  });

  factory VideoSource.fromMap(Map<String, dynamic> data) {
    final rawUrl = (data['url'] ?? data['videoUrl'] ?? '').toString().trim();
    final quality = data['quality']?.toString() ?? data['label']?.toString();

    int? parsedHeight;
    if (data['height'] != null) {
      parsedHeight = _asInt(data['height']);
    } else if (quality != null) {
      final match = RegExp(r'(?<height>\d{3,4})p').firstMatch(quality);
      if (match != null) {
        parsedHeight = int.tryParse(match.namedGroup('height')!);
      }
    }

    return VideoSource(
      url: rawUrl,
      path: data['path']?.toString(),
      quality: quality,
      type: data['type']?.toString(),
      height: parsedHeight,
      bitrate: _asInt(data['bitrate']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      if (path != null) 'path': path,
      if (quality != null) 'quality': quality,
      if (type != null) 'type': type,
      if (height != null) 'height': height,
      if (bitrate != null) 'bitrate': bitrate,
    };
  }
}

class VideoPlaybackHls {
  final VideoSource manifest;
  final bool adaptive;
  final int? renditionCount;
  final int? segmentDurationSeconds;

  const VideoPlaybackHls({
    required this.manifest,
    this.adaptive = false,
    this.renditionCount,
    this.segmentDurationSeconds,
  });

  factory VideoPlaybackHls.fromMap(Map<String, dynamic> data) {
    final manifestMap = _asMap(data['manifest']) ?? const <String, dynamic>{};
    return VideoPlaybackHls(
      manifest: VideoSource.fromMap(manifestMap),
      adaptive: data['adaptive'] == true,
      renditionCount: _asInt(data['renditionCount']),
      segmentDurationSeconds: _asInt(data['segmentDurationSeconds']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'manifest': manifest.toMap(),
      'adaptive': adaptive,
      if (renditionCount != null) 'renditionCount': renditionCount,
      if (segmentDurationSeconds != null)
        'segmentDurationSeconds': segmentDurationSeconds,
    };
  }

  bool get isAdaptiveReady =>
      manifest.url.isNotEmpty && adaptive && (renditionCount ?? 0) >= 2;
}

class VideoPlaybackContract {
  final int version;
  final String? mode;
  final List<VideoSource> renditionSources;
  final VideoSource? sourceAsset;
  final VideoSource? fallbackSource;
  final VideoPlaybackHls? hls;

  const VideoPlaybackContract({
    this.version = 1,
    this.mode,
    this.renditionSources = const [],
    this.sourceAsset,
    this.fallbackSource,
    this.hls,
  });

  factory VideoPlaybackContract.fromMap(Map<String, dynamic> data) {
    final sourceAssetMap = _asMap(data['sourceAsset']);
    final fallbackMap = _asMap(data['fallback']);
    final hlsMap = _asMap(data['hls']);

    return VideoPlaybackContract(
      version: _asInt(data['version']) ?? 1,
      mode: data['mode']?.toString(),
      renditionSources: _parseVideoSources(data['sources']),
      sourceAsset: sourceAssetMap != null && sourceAssetMap.isNotEmpty
          ? VideoSource.fromMap(sourceAssetMap)
          : null,
      fallbackSource: fallbackMap != null && fallbackMap.isNotEmpty
          ? VideoSource.fromMap(fallbackMap)
          : null,
      hls: hlsMap != null && hlsMap.isNotEmpty
          ? VideoPlaybackHls.fromMap(hlsMap)
          : null,
    );
  }

  List<VideoSource> get sources => _dedupeVideoSources([
        ...mp4Sources,
        if (hls?.manifest.url.isNotEmpty ?? false) hls!.manifest,
      ]);

  List<VideoSource> get mp4Sources => _dedupeVideoSources([
        ...renditionSources.where((source) => !source.isHls),
        if ((fallbackSource?.url.isNotEmpty ?? false) &&
            !(fallbackSource?.isHls ?? false))
          fallbackSource!,
        if ((sourceAsset?.url.isNotEmpty ?? false) &&
            !(sourceAsset?.isHls ?? false))
          sourceAsset!,
      ]);

  bool get hasMultipleMp4Sources => mp4Sources.length > 1;

  String effectiveModeForSourceType(String? sourceType) {
    if (sourceType == 'hls') {
      return mode ??
          (isAdaptiveHlsReady ? 'multi_rendition_hls' : 'single_rendition_hls');
    }
    return hasMultipleMp4Sources ? 'multi_rendition_mp4' : 'mp4_only';
  }

  String? get hlsManifestUrl {
    final manifest = hls?.manifest.url;
    if (manifest == null || manifest.isEmpty) {
      return null;
    }
    return manifest;
  }

  bool get isAdaptiveHlsReady =>
      mode == 'multi_rendition_hls' && (hls?.isAdaptiveReady ?? false);

  Map<String, dynamic> toMap() {
    return {
      'version': version,
      if (mode != null) 'mode': mode,
      if (renditionSources.isNotEmpty)
        'sources': renditionSources.map((source) => source.toMap()).toList(),
      if (sourceAsset != null) 'sourceAsset': sourceAsset!.toMap(),
      if (fallbackSource != null) 'fallback': fallbackSource!.toMap(),
      if (hls != null) 'hls': hls!.toMap(),
    };
  }
}

class Video {
  String id;
  String videoUrl;
  String thumbnailUrl;
  String description;
  String caption;
  String profilePhoto;
  String uid;
  List<String> likes;
  int shareCount;
  List<String> reports;
  int reportCount;
  String? status;
  List<VideoSource> sources;
  VideoPlaybackContract? playback;
  String? resolvedUrl;

  Video({
    required this.id,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.description,
    required this.caption,
    required this.profilePhoto,
    required this.uid,
    this.likes = const [],
    this.shareCount = 0,
    this.reports = const [],
    this.reportCount = 0,
    this.status,
    this.sources = const [],
    this.playback,
    this.resolvedUrl,
  });

  factory Video.fromMap(Map<String, dynamic> map) {
    String readString(dynamic value) =>
        value == null ? '' : value.toString().trim();

    final legacySources = _parseVideoSources(map['sources']);

    final playbackMap = _asMap(map['playback']);
    final playback = playbackMap != null && playbackMap.isNotEmpty
        ? VideoPlaybackContract.fromMap(playbackMap)
        : null;

    final mergedSources = _dedupeVideoSources([
      ...?playback?.sources,
      ...legacySources,
    ]);

    final fallbackUrl = readString(map['videoUrl']);
    final playbackPrimaryUrl =
        (playback?.fallbackSource?.url.isNotEmpty ?? false)
            ? playback!.fallbackSource!.url
            : (playback?.sourceAsset?.url.isNotEmpty ?? false)
                ? playback!.sourceAsset!.url
                : '';
    final inferredUrl = playbackPrimaryUrl.isNotEmpty
        ? playbackPrimaryUrl
        : fallbackUrl.isNotEmpty
            ? fallbackUrl
            : (playback?.mp4Sources.isNotEmpty ?? false)
                ? playback!.mp4Sources.first.url
                : (mergedSources.isNotEmpty ? mergedSources.first.url : '');

    return Video(
      id: map['id']?.toString() ?? '',
      videoUrl: inferredUrl,
      thumbnailUrl: readString(
        map['thumbnail'] ?? map['thumbnailUrl'] ?? map['thumbnailPath'],
      ),
      description: readString(
        map['description'] ?? map['songName'] ?? map['title'],
      ),
      caption: readString(
        map['caption'] ??
            map['captionText'] ??
            map['legend'] ??
            map['legende'] ??
            map['légende'],
      ),
      profilePhoto: readString(map['profilePhoto']),
      uid: readString(map['uid']),
      likes: List<String>.from(map['likes'] ?? const <String>[]),
      shareCount: _asInt(map['shareCount']) ?? 0,
      reports: List<String>.from(map['reports'] ?? const <String>[]),
      reportCount: _asInt(map['reportCount']) ?? 0,
      status: map['status']?.toString(),
      sources: mergedSources,
      playback: playback,
    );
  }

  factory Video.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Video.fromMap({
      ...data,
      'id': data['id'] ?? doc.id,
    });
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'videoUrl': videoUrl,
      'thumbnail': thumbnailUrl,
      'description': description,
      'songName': description,
      'caption': caption,
      'profilePhoto': profilePhoto,
      'uid': uid,
      'likes': likes,
      'shareCount': shareCount,
      'reports': reports,
      'reportCount': reportCount,
      'status': status,
      'sources': sources.map((source) => source.toMap()).toList(),
      if (playback != null) 'playback': playback!.toMap(),
    };
  }

  String get effectiveUrl {
    if (resolvedUrl != null && resolvedUrl!.isNotEmpty) {
      return resolvedUrl!;
    }
    if (videoUrl.isNotEmpty) {
      return videoUrl;
    }
    if (sources.isNotEmpty) {
      return sources.first.url;
    }
    return '';
  }

  bool get hasHlsSource =>
      playback?.hlsManifestUrl?.isNotEmpty == true ||
      sources.any((source) => source.isHls);

  bool get hasAdaptiveHlsSource => playback?.isAdaptiveHlsReady == true;

  bool get hasMultipleMp4Sources {
    final contract = playback;
    if (contract != null) {
      return contract.hasMultipleMp4Sources;
    }
    return sources.where((source) => !source.isHls).length > 1;
  }
}
