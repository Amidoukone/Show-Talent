class Video {
  String id;
  String videoUrl;
  String thumbnail;
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
    this.thumbnail = '', // Valeur par défaut si null
    this.songName = '',
    this.caption = '',
    this.profilePhoto = '',
    required this.uid,
    this.likes = const [],
    this.shareCount = 0,
    this.reports = const [],
    this.reportCount = 0,
  });

  // Méthode pour convertir des données Firestore en objet Video
  factory Video.fromMap(Map<String, dynamic> map) {
    return Video(
      id: map['id'] ?? '', // Valeur par défaut si 'id' est null
      videoUrl: map['videoUrl'] ?? '', // Assurez-vous que la vidéo est présente
      thumbnail: map['thumbnail'] ?? '', // Valeur par défaut
      songName: map['songName'] ?? '', // Valeur par défaut
      caption: map['caption'] ?? '', // Valeur par défaut
      profilePhoto: map['profilePhoto'] ?? '', // Valeur par défaut
      uid: map['uid'] ?? '',
      likes: List<String>.from(map['likes'] ?? []),
      shareCount: map['shareCount'] ?? 0,
      reports: List<String>.from(map['reports'] ?? []),
      reportCount: map['reportCount'] ?? 0,
    );
  }

  // Méthode pour convertir l'objet Video en données Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'videoUrl': videoUrl,
      'thumbnail': thumbnail,
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
