import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/models/message_converstion.dart';
import 'package:adfoot/controller/auth_controller.dart';

class ChatController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<List<Conversation>> _conversations = Rx<List<Conversation>>([]);
  List<Conversation> get conversations => _conversations.value;

  @override
  void onInit() {
    super.onInit();
    _fetchUserConversations();
  }

  /// Récupérer les conversations de l'utilisateur actuel
  void _fetchUserConversations() {
    final currentUserId = AuthController.instance.user?.uid;

    if (currentUserId == null) {
      print(" Utilisateur non connecté, impossible de charger les conversations.");
      _conversations.value = [];
      return;
    }

    _firestore
        .collection('conversations')
        .where('utilisateurIds', arrayContains: currentUserId)
        .snapshots()
        .listen((snapshot) async {
      try {
        _conversations.value = await Future.wait(snapshot.docs.map((doc) async {
          final conversationData = doc.data();
          final conversation = Conversation.fromMap(conversationData);

          // Calculer les messages non lus pour cette conversation
          final unreadCount = await _getUnreadMessageCount(doc.id, currentUserId);
          conversation.unreadMessagesCount = unreadCount;

          return conversation;
        }).toList());
      } catch (e) {
        print(" Erreur lors du chargement des conversations : $e");
      }
    });
  }

  /// Compter les messages non lus pour un utilisateur dans une conversation
  Future<int> _getUnreadMessageCount(String conversationId, String userId) async {
    try {
      final snapshot = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('destinataireId', isEqualTo: userId)
          .where('estLu', isEqualTo: false)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print(" Erreur lors du comptage des messages non lus : $e");
      return 0;
    }
  }

  /// Créer ou récupérer une conversation existante
  Future<String> createOrGetConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    try {
      // Rechercher une conversation existante
      final query = await _firestore
          .collection('conversations')
          .where('utilisateurIds', arrayContains: currentUserId)
          .get();

      for (var doc in query.docs) {
        final utilisateurIds = List<String>.from(doc['utilisateurIds'] ?? []);
        if (utilisateurIds.contains(otherUserId)) {
          return doc.id;
        }
      }

      // Créer une nouvelle conversation
      final conversationRef = _firestore.collection('conversations').doc();

      final newConversation = Conversation(
        id: conversationRef.id,
        utilisateur1Id: currentUserId,
        utilisateur2Id: otherUserId,
        utilisateurIds: [currentUserId, otherUserId],
      );

      await conversationRef.set(newConversation.toMap());
      return conversationRef.id;
    } catch (e) {
      print(" Erreur lors de la création/récupération de la conversation : $e");
      rethrow;
    }
  }

  /// Récupérer les messages d'une conversation
  Stream<List<Message>> getMessages(String conversationId) {
    if (conversationId.isEmpty) {
      print(" Erreur : conversationId est vide.");
      return const Stream.empty();
    }

    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('dateEnvoi', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Message.fromMap(doc.data());
      }).toList();
    });
  }

  /// Envoyer un message avec notification
  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String recipientId,
    required String content,
  }) async {
    try {
      final message = Message(
        id: '',
        expediteurId: senderId,
        destinataireId: recipientId,
        contenu: content,
        dateEnvoi: DateTime.now(),
        estLu: false,
      );

      final messageRef = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc();
      await messageRef.set(message.toMap());

      await _firestore.collection('conversations').doc(conversationId).update({
        'lastMessage': content,
        'lastMessageDate': Timestamp.now(),
      });

      final recipientDoc =
          await _firestore.collection('users').doc(recipientId).get();
      final recipientData = recipientDoc.data();

      if (recipientData != null && recipientData['fcmToken'] != null) {
        final fcmToken = recipientData['fcmToken'];
        await PushNotificationService.sendNotification(
          title: 'Nouveau message',
          body: content,
          token: fcmToken,
          contextType: 'message',
          contextData: conversationId,
        );
      }
    } catch (e) {
      print(" Erreur lors de l'envoi du message : $e");
    }
  }

  /// Marquer un message comme lu
  Future<void> markMessageAsRead({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .update({'estLu': true});
    } catch (e) {
      print(" Erreur lors de la mise à jour du message : $e");
    }
  }

  /// Marquer tous les messages non lus comme lus
  Future<void> markMessagesAsRead(String conversationId, String userId) async {
    try {
      final unreadMessages = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('destinataireId', isEqualTo: userId)
          .where('estLu', isEqualTo: false)
          .get();

      for (var doc in unreadMessages.docs) {
        await doc.reference.update({'estLu': true});
      }
    } catch (e) {
      print(" Erreur lors de la mise à jour des messages lus : $e");
    }
  }

  /// Supprimer un message
  Future<void> deleteMessage(String conversationId, String messageId) async {
    try {
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (e) {
      print(" Erreur lors de la suppression du message : $e");
    }
  }

  /// Supprimer une conversation entière
  Future<void> deleteConversation(String conversationId) async {
    try {
      final snapshot = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }

      await _firestore.collection('conversations').doc(conversationId).delete();
    } catch (e) {
      print(" Erreur lors de la suppression de la conversation : $e");
    }
  }
}
