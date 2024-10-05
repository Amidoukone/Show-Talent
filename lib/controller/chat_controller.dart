import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/user_controller.dart';
import 'package:show_talent/models/message_converstion.dart';
import 'package:show_talent/models/user.dart';

class ChatController extends GetxController {
  final Rx<List<Conversation>> _conversations = Rx<List<Conversation>>([]);
  List<Conversation> get conversations => _conversations.value;

  final Rx<List<Message>> _messages = Rx<List<Message>>([]); // Liste des messages observable
  List<Message> get messages => _messages.value; // Getter pour accéder aux messages dans l'UI

  late AppUser currentUser; // Utilisateur courant

  // Cache pour éviter de recharger les mêmes utilisateurs plusieurs fois
  final Map<String, AppUser> _userCache = {};

  @override
  void onInit() {
    super.onInit();
    _initializeCurrentUser();
    _fetchConversations();
  }

  // Initialiser l'utilisateur actuel
  void _initializeCurrentUser() {
    currentUser = Get.find<UserController>().user!;
  }

  // Méthode pour récupérer les conversations depuis Firestore
  void _fetchConversations() {
    FirebaseFirestore.instance
        .collection('conversations')
        .where('utilisateurIds', arrayContains: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      _conversations.value = snapshot.docs.map((doc) {
        return Conversation.fromMap(doc.data());
      }).toList();
    });
  }

  // Créer une nouvelle conversation
  Future<String> createConversation(AppUser currentUser, AppUser otherUser) async {
    String conversationId = FirebaseFirestore.instance.collection('conversations').doc().id;

    // Créer la conversation avec les deux utilisateurs
    Conversation newConversation = Conversation(
      id: conversationId,
      utilisateur1Id: currentUser.uid,
      utilisateur2Id: otherUser.uid,
      messages: [],
    );

    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .set(newConversation.toMap());

    return conversationId;
  }

  // Méthode pour envoyer un message dans une conversation
  Future<void> sendMessage(String conversationId, Message message) async {
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .add(message.toMap());

    // Ajouter le message localement pour l'UI en temps réel
    _messages.value.add(message);
    _messages.refresh();
  }

  // Méthode pour récupérer les messages d'une conversation
  void fetchMessages(String conversationId) {
    FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('dateEnvoi', descending: true) // Messages triés par date
        .snapshots()
        .listen((snapshot) {
      _messages.value = snapshot.docs.map((doc) {
        return Message.fromMap(doc.data());
      }).toList();
    });
  }

  // Méthode pour récupérer un utilisateur à partir de son ID
  Future<AppUser?> getUserById(String userId) async {
    // Si l'utilisateur est déjà en cache, on le renvoie
    if (_userCache.containsKey(userId)) {
      return _userCache[userId];
    }

    // Si l'utilisateur n'est pas en cache, on le récupère depuis Firestore
    try {
      DocumentSnapshot userSnapshot =
          await FirebaseFirestore.instance.collection('users').doc(userId).get();
      AppUser user = AppUser.fromMap(userSnapshot.data() as Map<String, dynamic>);

      // Mettre l'utilisateur dans le cache
      _userCache[userId] = user;
      return user;
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer les informations utilisateur.');
      return null;
    }
  }
}
