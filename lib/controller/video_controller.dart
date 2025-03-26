import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/video.dart';

class VideoController extends GetxController {
  var videoList = <Video>[].obs;
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoading = false;
  static const int _limit = 10;

  @override
  void onInit() {
    super.onInit();
    fetchPaginatedVideos();
  }

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  /// Chargement initial + pagination
  Future<void> fetchPaginatedVideos() async {
    if (_isLoading || !_hasMore) return;

    _isLoading = true;
    try {
      Query query = FirebaseFirestore.instance
          .collection('videos')
          .orderBy('createdAt', descending: true)
          .limit(_limit);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        final newVideos = snapshot.docs.map((doc) {
          try {
            return Video.fromMap(doc.data() as Map<String, dynamic>);
          } catch (e) {
            print('Erreur parsing vidéo : $e');
            return null;
          }
        }).whereType<Video>().toList();

        _lastDocument = snapshot.docs.last;
        videoList.addAll(newVideos);
      }

      if (snapshot.docs.length < _limit) {
        _hasMore = false;
      }
    } catch (e) {
      print('Erreur chargement vidéos : $e');
      Get.snackbar('Erreur', 'Impossible de charger les vidéos');
    } finally {
      _isLoading = false;
    }
  }

  /// Like / Unlike vidéo
  Future<void> likeVideo(String videoId, String userId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await ref.get();

      if (!doc.exists) return;

      final videoData = doc.data() as Map<String, dynamic>;
      final List<String> likes = List<String>.from(videoData['likes'] ?? []);

      if (likes.contains(userId)) {
        likes.remove(userId);
      } else {
        likes.add(userId);
      }

      await ref.update({'likes': likes});
    } catch (e) {
      print("Erreur lors de la mise à jour des likes : $e");
      Get.snackbar('Erreur', 'Impossible de mettre à jour les likes.');
    }
  }

  /// Partage vidéo
  Future<void> partagerVideo(String videoId, String videoUrl) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await ref.get();

      if (!doc.exists) return;

      final videoData = doc.data() as Map<String, dynamic>;
      int shareCount = videoData['shareCount'] ?? 0;
      shareCount++;

      await ref.update({'shareCount': shareCount});
    } catch (e) {
      print("Erreur lors du partage : $e");
      Get.snackbar('Erreur', 'Erreur lors du partage de la vidéo.');
    }
  }

  /// Signaler vidéo
  Future<void> signalerVideo(String videoId, String userId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await ref.get();

      if (!doc.exists) return;

      final videoData = doc.data() as Map<String, dynamic>;
      List<String> reports = List<String>.from(videoData['reports'] ?? []);
      int reportCount = videoData['reportCount'] ?? 0;

      if (!reports.contains(userId)) {
        reports.add(userId);
        reportCount++;
        await ref.update({
          'reports': reports,
          'reportCount': reportCount,
        });
        Get.snackbar('Succès', 'Vidéo signalée avec succès.');
      } else {
        Get.snackbar('Info', 'Vous avez déjà signalé cette vidéo.');
      }
    } catch (e) {
      print("Erreur signalement : $e");
      Get.snackbar('Erreur', 'Erreur lors du signalement.');
    }
  }

  /// Supprimer vidéo
  Future<void> deleteVideo(String videoId) async {
    try {
      await FirebaseFirestore.instance.collection('videos').doc(videoId).delete();
      videoList.removeWhere((video) => video.id == videoId);
      Get.snackbar('Succès', 'Vidéo supprimée avec succès.');
    } catch (e) {
      print("Erreur suppression : $e");
      Get.snackbar('Erreur', 'Erreur lors de la suppression de la vidéo.');
    }
  }

  /// Reset pagination et recharge depuis le début (optionnel)
  Future<void> refreshVideos() async {
    _lastDocument = null;
    _hasMore = true;
    videoList.clear();
    await fetchPaginatedVideos();
  }
}
