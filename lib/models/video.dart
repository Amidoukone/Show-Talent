class Video {
  String id;
  String videoUrl;
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
  });

  factory Video.fromMap(Map<String, dynamic> map) {
    return Video(
      id: map['id'] ?? '',
      videoUrl: map['videoUrl'] ?? '',
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
    );
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
    };
  }
}
