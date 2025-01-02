class Video {
  String id;
  String videoUrl;
  String thumbnailUrl; // Renommé pour correspondre à son utilisation
  String songName;
  String caption;
  String profilePhoto;
  String uid;
  List<String> likes;
  int shareCount;
  List<String> reports;
  int reportCount;

  Video({
    required this.id,
    required this.videoUrl,
    required this.thumbnailUrl, // Renommé ici
    required this.songName,
    required this.caption,
    required this.profilePhoto,
    required this.uid,
    this.likes = const [],
    this.shareCount = 0,
    this.reports = const [],
    this.reportCount = 0,
  });

  factory Video.fromMap(Map<String, dynamic> map) {
    return Video(
      id: map['id'] ?? '',
      videoUrl: map['videoUrl'] ?? '',
      thumbnailUrl: map['thumbnail'] ?? '', // Mapping pour correspondre à 'thumbnailUrl'
      songName: map['songName'] ?? '',
      caption: map['caption'] ?? '',
      profilePhoto: map['profilePhoto'] ?? '',
      uid: map['uid'] ?? '',
      likes: List<String>.from(map['likes'] ?? []),
      shareCount: map['shareCount'] ?? 0,
      reports: List<String>.from(map['reports'] ?? []),
      reportCount: map['reportCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'videoUrl': videoUrl,
      'thumbnail': thumbnailUrl, // Assurez-vous de correspondre au champ Firebase
      'songName': songName,
      'caption': caption,
      'profilePhoto': profilePhoto,
      'uid': uid,
      'likes': likes,
      'shareCount': shareCount,
      'reports': reports,
      'reportCount': reportCount,
    };
  }
}
