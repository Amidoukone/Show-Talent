import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/video.dart';
import 'package:get/get.dart';

class VideoController extends GetxController {
  var videoList = <Video>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetchVideos();
  }

  void fetchVideos() async {
    var snapshot = await FirebaseFirestore.instance.collection('videos').get();
    var videos = snapshot.docs.map((doc) => Video.fromMap(doc.data())).toList();
    videoList.assignAll(videos);
  }

  void likeVideo(String videoId, String userId) {
    // Logique pour aimer la vidéo
  }
}
