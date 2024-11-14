import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/video.dart';

class VideoController extends GetxController {
  var videoList = <Video>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetchVideos();
  }

  // Méthode pour récupérer les vidéos depuis Firestore
  void fetchVideos() {
    FirebaseFirestore.instance.collection('videos').snapshots().listen((snapshot) {
      videoList.assignAll(
        snapshot.docs.map((doc) {
          try {
            return Video.fromMap(doc.data());
          } catch (e) {
            print('Erreur lors de la récupération de la vidéo: $e');
            return null;
          }
        }).whereType<Video>().toList(),
      );
    });
  }

  // Méthode pour aimer ou retirer le like d'une vidéo
  Future<void> likeVideo(String videoId, String userId) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('videos').doc(videoId).get();
      if (doc.exists) {
        var videoData = doc.data() as Map<String, dynamic>;
        List<String> likes = List<String>.from(videoData['likes'] ?? []);
        if (likes.contains(userId)) {
          likes.remove(userId);
        } else {
          likes.add(userId);
        }
        await FirebaseFirestore.instance.collection('videos').doc(videoId).update({'likes': likes});
      }
    } catch (e) {
      print("Erreur lors de la mise à jour des likes : $e");
      Get.snackbar('Erreur', 'Impossible de mettre à jour les likes.');
    }
  }

  // Méthode pour partager une vidéo en incrémentant le compteur de partages
  Future<void> partagerVideo(String videoId) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('videos').doc(videoId).get();
      if (doc.exists) {
        var videoData = doc.data() as Map<String, dynamic>;
        int shareCount = videoData['shareCount'] ?? 0;
        shareCount++;

        await FirebaseFirestore.instance.collection('videos').doc(videoId).update({'shareCount': shareCount});
        Get.snackbar('Succès', 'Vidéo partagée avec succès !');
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors du partage de la vidéo.');
      print("Erreur lors du partage de la vidéo : $e");
    }
  }

  // Méthode pour signaler une vidéo inappropriée
  Future<void> signalerVideo(String videoId, String userId) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('videos').doc(videoId).get();
      if (doc.exists) {
        var videoData = doc.data() as Map<String, dynamic>;
        List<String> reports = List<String>.from(videoData['reports'] ?? []);
        int reportCount = videoData['reportCount'] ?? 0;

        if (!reports.contains(userId)) {
          reports.add(userId);
          reportCount++;

          await FirebaseFirestore.instance.collection('videos').doc(videoId).update({
            'reports': reports,
            'reportCount': reportCount,
          });

          Get.snackbar('Succès', 'Vidéo signalée avec succès.');
        } else {
          Get.snackbar('Erreur', 'Vous avez déjà signalé cette vidéo.');
        }
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors du signalement de la vidéo.');
      print("Erreur lors du signalement de la vidéo : $e");
    }
  }

  // Méthode pour supprimer une vidéo de Firestore et de la liste locale
  Future<void> deleteVideo(String videoId) async {
    try {
      await FirebaseFirestore.instance.collection('videos').doc(videoId).delete();
      videoList.removeWhere((video) => video.id == videoId);
      Get.snackbar('Succès', 'Vidéo supprimée avec succès.');
    } catch (e) {
      Get.snackbar('Erreur', 'Erreur lors de la suppression de la vidéo.');
      print("Erreur lors de la suppression de la vidéo : $e");
    }
  }
}
