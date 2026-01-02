import 'package:cloud_firestore/cloud_firestore.dart';

/// ---------------------------------------------------------------------------
/// VideoSource
/// - Représente une source vidéo alternative (mp4, hls, différentes qualités)
/// - Totalement optionnelle (fallback sur videoUrl garanti)
/// ---------------------------------------------------------------------------
class VideoSource {
  final String url;
  final String? quality; // ex: "720p", "480p"
  final String? type; // ex: "mp4", "hls"
  final int? height;
  final int? bitrate;

  bool get isHls =>
      (type?.toLowerCase() == 'hls') || url.toLowerCase().contains('.m3u8');

  const VideoSource({
    required this.url,
    this.quality,
    this.type,
    this.height,
    this.bitrate,
  });

  factory VideoSource.fromMap(Map<String, dynamic> data) {
    final rawUrl = (data['url'] ?? data['videoUrl'] ?? '').toString();
    final quality =
        data['quality']?.toString() ?? data['label']?.toString();

    int? parsedHeight;
    if (data['height'] != null) {
      parsedHeight = (data['height'] as num?)?.toInt();
    } else if (quality != null) {
      final match =
          RegExp(r'(?<height>\d{3,4})p').firstMatch(quality);
      if (match != null) {
        parsedHeight =
            int.tryParse(match.namedGroup('height')!);
      }
    }

    return VideoSource(
      url: rawUrl,
      quality: quality,
      type: data['type']?.toString(),
      height: parsedHeight,
      bitrate: (data['bitrate'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      if (quality != null) 'quality': quality,
      if (type != null) 'type': type,
      if (height != null) 'height': height,
      if (bitrate != null) 'bitrate': bitrate,
    };
  }
}

/// ---------------------------------------------------------------------------
/// Video (modèle principal)
/// - Rétro-compatible avec l’existant
/// - Prêt pour sources multiples & HLS
/// ---------------------------------------------------------------------------
class Video {
  String id;
  String videoUrl; // fallback principal (legacy)
  String thumbnailUrl;
  String songName;
  String caption;
  String profilePhoto;
  String uid;
  List<String> likes;
  int shareCount;
  List<String> reports;
  int reportCount;
  String? status;

  /// Nouvelles capacités (optionnelles)
  List<VideoSource> sources;
  String? resolvedUrl; // URL effectivement choisie par VideoManager

  Video({
    required this.id,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.songName,
    required this.caption,
    required this.profilePhoto,
    required this.uid,
    this.likes = const [],
    this.shareCount = 0,
    this.reports = const [],
    this.reportCount = 0,
    this.status,
    this.sources = const [],
    this.resolvedUrl,
  });

  factory Video.fromMap(Map<String, dynamic> map) {
    final rawSources = (map['sources'] as List?)
            ?.map((e) => VideoSource.fromMap(
                (e ?? {}) as Map<String, dynamic>))
            .where((s) => s.url.isNotEmpty)
            .toList() ??
        const <VideoSource>[];

    final fallbackUrl = (map['videoUrl'] ?? '').toString();
    final inferredUrl = fallbackUrl.isNotEmpty
        ? fallbackUrl
        : (rawSources.isNotEmpty ? rawSources.first.url : '');

    return Video(
      id: map['id'] ?? '',
      videoUrl: inferredUrl,
      thumbnailUrl: map['thumbnail'] ?? '',
      songName: map['songName'] ?? '',
      caption: map['caption'] ?? '',
      profilePhoto: map['profilePhoto'] ?? '',
      uid: map['uid'] ?? '',
      likes: List<String>.from(map['likes'] ?? []),
      shareCount: map['shareCount'] ?? 0,
      reports: List<String>.from(map['reports'] ?? []),
      reportCount: map['reportCount'] ?? 0,
      status: map['status'],
      sources: rawSources,
    );
  }

  factory Video.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
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
      'songName': songName,
      'caption': caption,
      'profilePhoto': profilePhoto,
      'uid': uid,
      'likes': likes,
      'shareCount': shareCount,
      'reports': reports,
      'reportCount': reportCount,
      'status': status,
      'sources': sources.map((s) => s.toMap()).toList(),
    };
  }

  /// -------------------------------------------------------------------------
  /// Helpers sûrs (utilisés par VideoManager)
  /// -------------------------------------------------------------------------

  /// URL finale à utiliser par le player
  String get effectiveUrl {
    if (resolvedUrl != null && resolvedUrl!.isNotEmpty) {
      return resolvedUrl!;
    }
    if (videoUrl.isNotEmpty) return videoUrl;
    if (sources.isNotEmpty) return sources.first.url;
    return '';
  }

  bool get hasHlsSource => sources.any((s) => s.isHls);
}
