class Video {
  String id;
  String videoUrl;
  String thumbnail;
  String songName;
  String caption;
  String profilePhoto;
  String uid;
  List<String> likes;
  int commentCount;
  int shareCount;

  Video({
    required this.id,
    required this.videoUrl,
    required this.thumbnail,
    required this.songName,
    required this.caption,
    required this.profilePhoto,
    required this.uid,
    required this.likes,
    required this.commentCount,
    required this.shareCount,
  });

  // Méthode pour convertir des données Firestore en objet Video
  factory Video.fromMap(Map<String, dynamic> map) {
    return Video(
      id: map['id'],
      videoUrl: map['videoUrl'],
      thumbnail: map['thumbnail'],
      songName: map['songName'],
      caption: map['caption'],
      profilePhoto: map['profilePhoto'],
      uid: map['uid'],
      likes: List<String>.from(map['likes']),
      commentCount: map['commentCount'],
      shareCount: map['shareCount'],
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
      'commentCount': commentCount,
      'shareCount': shareCount,
    };
  }
}
