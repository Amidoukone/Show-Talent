import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/video.dart';
import '../widgets/video_manager.dart';

class VideoController extends GetxController {
  var videoList = <Video>[].obs;
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoading = false;
  static const int _limit = 10;

  final VideoManager _videoManager = VideoManager();

  @override
  void onInit() {
    super.onInit();
    refreshVideos();
  }

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  Future<void> fetchPaginatedVideos({bool isRefresh = false}) async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;

    try {
      Query query = FirebaseFirestore.instance
          .collection('videos')
          .where('status', isEqualTo: 'ready')
          .orderBy('updatedAt', descending: true)
          .limit(_limit);

      if (!isRefresh && _lastDocument != null) {
        final updatedAt = _lastDocument!.get('updatedAt');
        if (updatedAt != null) {
          query = query.startAfter([updatedAt]);
        }
      }

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        final newVideos = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return Video.fromMap(data);
        }).toList();

        final existingIds = videoList.map((v) => v.id).toSet();
        final uniqueNewVideos = newVideos.where((v) => !existingIds.contains(v.id)).toList();

        if (isRefresh) {
          videoList.assignAll(uniqueNewVideos);
        } else {
          videoList.addAll(uniqueNewVideos);
        }

        _lastDocument = snapshot.docs.last;

        for (final video in uniqueNewVideos) {
          if (video.videoUrl.isNotEmpty) {
            await _videoManager.preload(video.videoUrl);
          }
        }
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

  Future<void> refreshVideos() async {
    _videoManager.disposeAll(); // ⚠️ Nettoyage complet avant rechargement
    _lastDocument = null;
    _hasMore = true;
    videoList.clear();
    await fetchPaginatedVideos(isRefresh: true);
  }

  Future<void> likeVideo(String videoId, String userId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await ref.get();
      if (!doc.exists) return;

      final videoData = doc.data()!;
      final List<String> likes = List<String>.from(videoData['likes'] ?? []);

      if (likes.contains(userId)) {
        likes.remove(userId);
      } else {
        likes.add(userId);
      }

      await ref.update({'likes': likes});
    } catch (e) {
      print("Erreur mise à jour des likes : $e");
      Get.snackbar('Erreur', 'Impossible de mettre à jour les likes.');
    }
  }

  Future<void> partagerVideo(String videoId, String videoUrl) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await ref.get();
      if (!doc.exists) return;

      int shareCount = doc.data()?['shareCount'] ?? 0;
      shareCount++;

      await ref.update({'shareCount': shareCount});
    } catch (e) {
      print("Erreur lors du partage : $e");
      Get.snackbar('Erreur', 'Erreur lors du partage de la vidéo.');
    }
  }

  Future<void> signalerVideo(String videoId, String userId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('videos').doc(videoId);
      final doc = await ref.get();
      if (!doc.exists) return;

      final data = doc.data()!;
      List<String> reports = List<String>.from(data['reports'] ?? []);
      int reportCount = data['reportCount'] ?? 0;

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

  Future<void> deleteVideo(String videoId) async {
    try {
      final videoToDelete = videoList.firstWhereOrNull((v) => v.id == videoId);
      if (videoToDelete != null) {
        _videoManager.dispose(videoToDelete.videoUrl); // ⛔ libération du contrôleur vidéo
      }

      await FirebaseFirestore.instance.collection('videos').doc(videoId).delete();
      videoList.removeWhere((video) => video.id == videoId);

      Get.snackbar('Succès', 'Vidéo supprimée avec succès.');
    } catch (e) {
      print("Erreur suppression : $e");
      Get.snackbar('Erreur', 'Erreur lors de la suppression de la vidéo.');
    }
  }
}
