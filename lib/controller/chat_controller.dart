
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/notification_controller.dart';
import 'package:show_talent/models/conversation.dart';
import 'package:show_talent/models/message.dart';
import 'package:show_talent/models/notification.dart';
import 'package:show_talent/models/user.dart';

class ChatController extends GetxController {
  final Rx<List<Conversation>> _conversations = Rx<List<Conversation>>([]);
  List<Conversation> get conversations => _conversations.value;

  final Rx<List<Message>> _messages = Rx<List<Message>>([]);
  List<Message> get messages => _messages.value;

  // Ajout des utilisateurs courant et cible
  late AppUser currentUser;
  late AppUser otherUser;

  // Controller des notifications
  final NotificationController notificationController = Get.put(NotificationController());

  @override
  void onInit() {
    super.onInit();
    _fetchConversations();
  }

  void initUsers(AppUser current, AppUser other) {
    currentUser = current;
    otherUser = other;
  }

  void _fetchConversations() {
    FirebaseFirestore.instance
        .collection('conversations')
        .snapshots()
        .listen((snapshot) {
      _conversations.value = snapshot.docs
          .map((doc) => Conversation.fromMap(doc.data()))
          .toList();
      update();
    });
  }

  void fetchMessages(String conversationId) {
    FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('dateEnvoi')
        .snapshots()
        .listen((snapshot) {
      _messages.value = snapshot.docs
          .map((doc) => Message.fromMap(doc.data()))
          .toList();
      update();
    });
  }

  Future<void> sendMessage(String conversationId, Message message) async {
    try {
      // Envoyer le message dans la conversation
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .add(message.toMap());

      // Mettre à jour la conversation principale avec le nouveau message
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .update({
        'messages': FieldValue.arrayUnion([message.toMap()])
      });

      // Envoi d'une notification au destinataire (otherUser)
      NotificationModel notification = NotificationModel(
        id: FirebaseFirestore.instance.collection('notifications').doc().id,
        destinataire: otherUser, // L'utilisateur qui reçoit la notification
        message: '${currentUser.name} vous a envoyé un message.',
        type: 'message',
        dateCreation: DateTime.now(),
      );
      await notificationController.sendNotification(notification);

      Get.snackbar('Succès', 'Message envoyé');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de l\'envoi du message');
    }
  }

  Future<void> markAsRead(String conversationId, String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .update({'estLu': true});
      Get.snackbar('Message lu', 'Le message a été marqué comme lu');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la mise à jour du statut du message');
    }
  }

  Future<void> createConversation(AppUser utilisateur1, AppUser utilisateur2) async {
    try {
      String conversationId = FirebaseFirestore.instance
          .collection('conversations')
          .doc()
          .id;

      Conversation newConversation = Conversation(
        id: conversationId,
        utilisateur1: utilisateur1,
        utilisateur2: utilisateur2,
        messages: [],
      );

      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .set(newConversation.toMap());

      Get.snackbar('Succès', 'Nouvelle conversation créée');
    } catch (e) {
      Get.snackbar('Erreur', 'Échec de la création de la conversation');
    }
  }
}
