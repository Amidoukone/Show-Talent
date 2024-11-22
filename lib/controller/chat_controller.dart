import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/push_notification.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/message_converstion.dart';
import 'package:show_talent/models/user.dart';

class ChatController extends GetxController {
  final RxList<Conversation> _conversations = <Conversation>[].obs;
  List<Conversation> get conversations => _conversations;

  final RxList<Message> _messages = <Message>[].obs;
  List<Message> get messages => _messages;

  late AppUser currentUser;
  final Map<String, AppUser> _userCache = {};

  @override
  void onInit() {
    super.onInit();
    _initializeCurrentUser();
    fetchConversations();
  }

  // Initialiser l'utilisateur courant à partir du UserController
  void _initializeCurrentUser() {
    try {
      currentUser = Get.find<UserController>().user!;
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de charger les informations utilisateur.');
    }
  }

  // Récupérer toutes les conversations associées à l'utilisateur actuel
  void fetchConversations() {
    FirebaseFirestore.instance
        .collection('conversations')
        .where('utilisateurIds', arrayContains: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      _conversations.value = snapshot.docs.map((doc) {
        return Conversation.fromMap(doc.data());
      }).toList();
    }, onError: (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les conversations.');
    });
  }

  // Récupérer les messages d'une conversation spécifique
  void fetchMessages(String conversationId) {
    FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('dateEnvoi', descending: false)
        .snapshots()
        .listen((snapshot) async {
      List<Message> loadedMessages = snapshot.docs.map((doc) {
        return Message.fromMap(doc.data());
      }).toList();

      _messages.value = loadedMessages;

      // Marquer les messages reçus comme lus
      await _markUnreadMessagesAsRead(conversationId, loadedMessages);
    }, onError: (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les messages.');
    });
  }

  // Marquer les messages non lus comme lus
  Future<void> _markUnreadMessagesAsRead(String conversationId, List<Message> messages) async {
    try {
      for (Message message in messages) {
        if (message.destinataireId == currentUser.uid && !message.estLu) {
          await FirebaseFirestore.instance
              .collection('conversations')
              .doc(conversationId)
              .collection('messages')
              .doc(message.id)
              .update({'estLu': true});
        }
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de marquer les messages comme lus.');
    }
  }

  // Créer une nouvelle conversation ou obtenir une existante
  Future<String> createOrGetConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    try {
      // Vérifier si une conversation existe déjà
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('conversations')
          .where('utilisateurIds', arrayContains: currentUserId)
          .get();

      for (var doc in querySnapshot.docs) {
        List<dynamic> utilisateurIds = doc['utilisateurIds'];
        if (utilisateurIds.contains(otherUserId)) {
          return doc.id; // Retourner l'identifiant de la conversation existante
        }
      }

      // Si aucune conversation n'existe, en créer une nouvelle
      DocumentReference conversationRef = FirebaseFirestore.instance.collection('conversations').doc();

      await conversationRef.set({
        'id': conversationRef.id,
        'utilisateurIds': [currentUserId, otherUserId],
        'lastMessage': '',
        'lastMessageDate': Timestamp.now(),
      });

      return conversationRef.id; // Retourner l'identifiant de la nouvelle conversation
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de créer ou récupérer la conversation.');
      rethrow;
    }
  }

  // Obtenir le nombre de messages non lus
  Future<int> getUnreadMessagesCount(String conversationId) async {
    try {
      QuerySnapshot unreadMessagesSnapshot = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('destinataireId', isEqualTo: currentUser.uid)
          .where('estLu', isEqualTo: false)
          .get();

      return unreadMessagesSnapshot.docs.length;
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les messages non lus.');
      return 0;
    }
  }

  // Envoyer un message
  Future<void> sendMessage(String conversationId, Message message) async {
    try {
      DocumentReference messageRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc();

      await messageRef.set({
        ...message.toMap(),
        'id': messageRef.id, // Ajouter l'ID généré automatiquement
      });

      await FirebaseFirestore.instance.collection('conversations').doc(conversationId).update({
        'lastMessage': message.contenu,
        'lastMessageDate': Timestamp.fromDate(message.dateEnvoi),
      });

      // Notification push si nécessaire
      await _sendNotificationToReceiver(message);
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible d\'envoyer le message.');
    }
  }

  // Envoyer une notification push au destinataire
  Future<void> _sendNotificationToReceiver(Message message) async {
    try {
      DocumentSnapshot userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(message.destinataireId)
          .get();

      if (userSnapshot.exists) {
        String? fcmToken = userSnapshot.get('fcmToken');
        if (fcmToken != null && fcmToken.isNotEmpty) {
          await PushNotificationService.sendNotification(
            title: 'Nouveau message de ${currentUser.nom}',
            body: message.contenu,
            token: fcmToken,
            contextType: 'message',
            contextData: message.expediteurId,
          );
        }
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible d\'envoyer la notification push.');
    }
  }

  // Marquer tous les messages non lus d'une conversation comme lus
  Future<void> markMessagesAsRead(String conversationId) async {
    try {
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
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de marquer les messages comme lus.');
    }
  }

  // Récupérer un utilisateur par son ID avec mise en cache
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

  // Supprimer une conversation et tous ses messages
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
}
