import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ on écoute l’auth directement
import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/models/message_converstion.dart';
import 'package:adfoot/controller/auth_controller.dart';

class ChatController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const Duration _activeWindowTolerance = Duration(seconds: 25);

  final Rx<List<Conversation>> _conversations = Rx<List<Conversation>>([]);
  List<Conversation> get conversations => _conversations.value;

  // Subscriptions pour gérer proprement les (re)écoutes
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _convSub;

  @override
  void onInit() {
    super.onInit();
    // ✅ Écouter l’auth pour binder les conversations quand un user est prêt
    _authSub = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _unbindConversations();
        _conversations.value = [];
        return;
      }
      _bindConversationsFor(user.uid);
    });

    // Cold start: si déjà connecté (ex: token restauré), on force un bind
    final uid = AuthController.instance.currentUid ?? _auth.currentUser?.uid;
    if (uid != null) {
      _bindConversationsFor(uid);
    }
  }

  @override
  void onClose() {
    _authSub?.cancel();
    _unbindConversations();
    super.onClose();
  }

  /// Appel manuel si besoin (re-binde sur l’UID actuel)
  void refreshConversations() {
    final uid = AuthController.instance.currentUid ?? _auth.currentUser?.uid;
    if (uid == null) {
      _unbindConversations();
      _conversations.value = [];
      return;
    }
    _bindConversationsFor(uid);
  }

  /// (Re)branche le listener Firestore pour un user donné.
  void _bindConversationsFor(String userId) {
    _unbindConversations(); // évite les écoutes multiples

    _convSub = _firestore
        .collection('conversations')
        .where('utilisateurIds', arrayContains: userId)
        .snapshots()
        .listen((snapshot) async {
      try {
        final items = await Future.wait(snapshot.docs.map((doc) async {
          final data = doc.data();
          data['id'] = doc.id; // ✅ injecter l'id du doc
          final conv = Conversation.fromMap(data);

          // Non lus (pour badger)
          conv.unreadMessagesCount = await _getUnreadMessageCount(doc.id, userId);
          return conv;
        }).toList());

        _conversations.value = items;
      } catch (e) {
        // ignore: avoid_print
        print("Erreur lors du chargement des conversations : $e");
      }
    }, onError: (e) {
      // ignore: avoid_print
      print("Erreur écoute conversations : $e");
    });
  }

  /// Annule l’écoute Firestore des conversations
  void _unbindConversations() {
    _convSub?.cancel();
    _convSub = null;
  }

  /// Compte les messages non lus pour un utilisateur dans une conversation
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
      // ignore: avoid_print
      print("Erreur lors du comptage des messages non lus : $e");
      return 0;
    }
  }

  /// Créer ou récupérer une conversation existante (1-1)
  Future<String> createOrGetConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    try {
      final query = await _firestore
          .collection('conversations')
          .where('utilisateurIds', arrayContains: currentUserId)
          .get();

      for (var doc in query.docs) {
        final ids = List<String>.from(doc['utilisateurIds'] ?? []);
        if (ids.contains(otherUserId)) {
          return doc.id;
        }
      }

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
      // ignore: avoid_print
      print("Erreur lors de la création/récupération de la conversation : $e");
      rethrow;
    }
  }

  /// Récupérer les messages d'une conversation
  Stream<List<Message>> getMessages(String conversationId) {
    if (conversationId.isEmpty) {
      // ignore: avoid_print
      print("Erreur : conversationId est vide.");
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
        final data = doc.data();
        data['id'] = doc.id; // ✅ expose l'ID du doc dans le modèle
        return Message.fromMap(data);
      }).toList();
    });
  }

  /// Envoi d'un message + notification si le destinataire n'est PAS en conversation active
  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String recipientId,
    required String content,
  }) async {
    try {
      final messageRef = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc();

      final message = Message(
        id: messageRef.id,
        expediteurId: senderId,
        destinataireId: recipientId,
        contenu: content,
        dateEnvoi: DateTime.now(),
        estLu: false,
      );

      // Écritures atomiques : message + meta conversation
      final batch = _firestore.batch();
      batch.set(messageRef, message.toMap());
      batch.update(
        _firestore.collection('conversations').doc(conversationId),
        {
          'lastMessage': content,
          'lastMessageDate': Timestamp.now(),
        },
      );
      await batch.commit();

      // Vérifier la présence / activité du destinataire
      final shouldNotify = await _shouldSendNotification(
        recipientId: recipientId,
        conversationId: conversationId,
      );

      if (!shouldNotify) {
        return; // ✅ On ne notifie pas si l'autre est déjà dans cette conversation
      }

      // Envoi FCM si token dispo
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
      // ignore: avoid_print
      print("Erreur lors de l'envoi du message : $e");
    }
  }

  /// Renvoie true si on DOIT envoyer une notification push,
  /// false si le destinataire est très probablement en train de discuter dans CETTE conversation.
  Future<bool> _shouldSendNotification({
    required String recipientId,
    required String conversationId,
  }) async {
    try {
      final doc = await _firestore.collection('users').doc(recipientId).get();
      if (!doc.exists) return true; // pas d'info -> on notifie par défaut

      final data = doc.data() ?? {};
      final activeConvId = data['activeConversationId'] as String?;
      final ts = data['activeAt'] as Timestamp?;
      final activeAt = ts?.toDate();

      // Si l'utilisateur regarde justement CETTE conversation et a été actif récem­ment,
      // on considère que la notification est inutile (discussion instantanée).
      if (activeConvId == conversationId && activeAt != null) {
        final isRecent =
            DateTime.now().difference(activeAt) <= _activeWindowTolerance;
        if (isRecent) return false;
      }

      return true;
    } catch (_) {
      // En cas d'erreur de lecture, on préfère notifier pour ne pas rater un push important.
      return true;
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
      // ignore: avoid_print
      print("Erreur lors de la mise à jour du message : $e");
    }
  }

  /// Marquer tous les messages non lus comme lus (pour un destinataire)
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
      // ignore: avoid_print
      print("Erreur lors de la mise à jour des messages lus : $e");
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
      // ignore: avoid_print
      print("Erreur lors de la suppression du message : $e");
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
      // ignore: avoid_print
      print("Erreur lors de la suppression de la conversation : $e");
    }
  }
}
