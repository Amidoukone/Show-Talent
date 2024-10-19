import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class FollowController extends GetxController {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> followUser(String currentUserId, String targetUserId) async {
    await firestore.collection('users').doc(currentUserId).update({
      'followingsList': FieldValue.arrayUnion([targetUserId]),
    });

    await firestore.collection('users').doc(targetUserId).update({
      'followersList': FieldValue.arrayUnion([currentUserId]),
    });
  }

  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    await firestore.collection('users').doc(currentUserId).update({
      'followingsList': FieldValue.arrayRemove([targetUserId]),
    });

    await firestore.collection('users').doc(targetUserId).update({
      'followersList': FieldValue.arrayRemove([currentUserId]),
    });
  }
}