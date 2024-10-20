import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/message_converstion.dart';
import 'package:show_talent/models/user.dart';

class ChatController extends GetxController {
  final Rx<List<Conversation>> _conversations = Rx<List<Conversation>>([]);
  List<Conversation> get conversations => _conversations.value;

  final Rx<List<Message>> _messages = Rx<List<Message>>([]);
  List<Message> get messages => _messages.value;

  late AppUser currentUser;
  final Map<String, AppUser> _userCache = {};

  @override
  void onInit() {
    super.onInit();
    _initializeCurrentUser();
    fetchConversations();
  }

  void _initializeCurrentUser() {
    currentUser = Get.find<UserController>().user!;
  }

  void fetchConversations() {
    FirebaseFirestore.instance
        .collection('conversations')
        .where('utilisateurIds', arrayContains: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      _conversations.value = snapshot.docs.map((doc) {
        return Conversation.fromMap(doc.data() as Map<String, dynamic>);
      }).toList();
    });
  }

  Future<String> createOrGetConversation({required String currentUserId, required String otherUserId}) async {
    QuerySnapshot existingConversations = await FirebaseFirestore.instance
        .collection('conversations')
        .where('utilisateurIds', arrayContains: currentUserId)
        .get();

    for (var doc in existingConversations.docs) {
      Conversation conversation = Conversation.fromMap(doc.data() as Map<String, dynamic>);
      if (conversation.utilisateurIds.contains(otherUserId)) {
        return conversation.id;
      }
    }

    String conversationId = FirebaseFirestore.instance.collection('conversations').doc().id;

    Conversation newConversation = Conversation(
      id: conversationId,
      utilisateur1Id: currentUserId,
      utilisateur2Id: otherUserId,
      utilisateurIds: [currentUserId, otherUserId],
      lastMessage: '',
    );

    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .set(newConversation.toMap());

    return conversationId;
  }

  void fetchMessages(String conversationId) {
    FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('dateEnvoi', descending: false)
        .snapshots()
        .listen((snapshot) {
      _messages.value = snapshot.docs.map((doc) {
        return Message.fromMap(doc.data() as Map<String, dynamic>);
      }).toList();
      _messages.refresh();
    });
  }

  Future<void> sendMessage(String conversationId, Message message) async {
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .add(message.toMap());

    await FirebaseFirestore.instance.collection('conversations').doc(conversationId).update({
      'lastMessage': message.contenu,
      'lastMessageDate': Timestamp.fromDate(message.dateEnvoi),
    });
  }

  Future<void> markMessagesAsRead(String conversationId) async {
    QuerySnapshot messagesSnapshot = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .where('destinataireId', isEqualTo: currentUser.uid)
        .where('estLu', isEqualTo: false)
        .get();

    for (var doc in messagesSnapshot.docs) {
      await doc.reference.update({'estLu': true});
    }
  }

  Future<int> getUnreadMessagesCount(String conversationId) async {
    QuerySnapshot messagesSnapshot = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .where('destinataireId', isEqualTo: currentUser.uid)
        .where('estLu', isEqualTo: false)
        .get();

    return messagesSnapshot.docs.length;
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .delete();
      Get.snackbar('Succès', 'Message supprimé.');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de supprimer le message.');
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      var messagesSnapshot = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .get();

      for (var doc in messagesSnapshot.docs) {
        await doc.reference.delete();
      }

      await FirebaseFirestore.instance.collection('conversations').doc(conversationId).delete();

      Get.snackbar('Succès', 'Conversation supprimée avec succès.');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de supprimer la conversation.');
    }
  }

  Future<AppUser?> getUserById(String userId) async {
    if (_userCache.containsKey(userId)) {
      return _userCache[userId];
    }

    try {
      DocumentSnapshot userSnapshot =
          await FirebaseFirestore.instance.collection('users').doc(userId).get();

      if (userSnapshot.exists) {
        AppUser user = AppUser.fromMap(userSnapshot.data() as Map<String, dynamic>);
        _userCache[userId] = user;
        return user;
      } else {
        return null;
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les informations utilisateur.');
      return null;
    }
  }
}
