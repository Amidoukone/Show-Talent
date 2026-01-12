import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/models/message_converstion.dart';
import 'package:adfoot/controller/auth_controller.dart';

class ChatController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const Duration _activeWindowTolerance = Duration(seconds: 25);

  final Rx<List<Conversation>> _conversations = Rx<List<Conversation>>([]);
  List<Conversation> get conversations => _conversations.value;

  final RxInt _totalUnread = 0.obs;
  int get totalUnread => _totalUnread.value;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _convSub;

  // ✅ protège contre les mises à jour async “en retard”
  int _bindEpoch = 0;
  String? _boundUid;

  @override
  void onInit() {
    super.onInit();

    // ✅ IMPORTANT : on aligne sur le même flux que UserController/AuthController
    // idTokenChanges couvre login/logout + reload/refresh/token updates.
    _authSub = _auth.idTokenChanges().listen(
      (user) {
        if (user == null) {
          _resetLocalState();
          _unbindConversations();
          _boundUid = null;
          return;
        }
        _bindConversationsFor(user.uid);
      },
      onError: (e) => print("ChatController auth listen error: $e"),
    );

    // ✅ Cold start : si déjà connecté
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

  /// Utilisable depuis l’UI (ex: ConversationsScreen initState)
  void refreshConversations() {
    final uid = AuthController.instance.currentUid ?? _auth.currentUser?.uid;
    if (uid == null) {
      _resetLocalState();
      _unbindConversations();
      _boundUid = null;
      return;
    }

    // ✅ si déjà bind sur le même uid, on peut juste “forcer” l’UI
    // mais on rebinde quand même si le sub est null.
    if (_boundUid == uid && _convSub != null) {
      _conversations.refresh();
      update();
      return;
    }

    _bindConversationsFor(uid);
  }

  void _resetLocalState() {
    _conversations.value = [];
    _totalUnread.value = 0;
    _conversations.refresh();
    update();
  }

  void _bindConversationsFor(String userId) {
    // ✅ évite rebinding inutile
    if (_boundUid == userId && _convSub != null) return;

    _boundUid = userId;

    // ✅ annule l’ancien bind
    _unbindConversations();

    // ✅ incrémente epoch : toutes les tâches async précédentes deviennent “stale”
    final int myEpoch = ++_bindEpoch;

    _convSub = _firestore
        .collection('conversations')
        .where('utilisateurIds', arrayContains: userId)
        // ✅ Optionnel: si tu as un index, tu peux décommenter pour un ordre stable
        // .orderBy('lastMessageDate', descending: true)
        .snapshots()
        .listen(
      (snapshot) async {
        try {
          // Si un nouveau bind a eu lieu pendant qu'on attendait, on stop.
          if (myEpoch != _bindEpoch) return;

          // ⚠️ On conserve ta logique : unreadMessagesCount calculé côté controller
          // (l’UI ne doit pas refaire un StreamBuilder par conversation)
          final items = await Future.wait(
            snapshot.docs.map((doc) async {
              final data = doc.data();
              data['id'] = doc.id;

              final conv = Conversation.fromMap(data);

              // unread count
              conv.unreadMessagesCount =
                  await _getUnreadMessageCount(doc.id, userId);

              return conv;
            }).toList(),
          );

          // Si stale après les awaits
          if (myEpoch != _bindEpoch) return;

          _conversations.value = items;
          _recalculateTotalUnread();

          // ✅ Très important : forcer le refresh UI (Obx + parfois GetBuilder ailleurs)
          _conversations.refresh();
          update();
        } catch (e) {
          print("Erreur lors du chargement des conversations : $e");
        }
      },
      onError: (e) => print("Erreur écoute conversations : $e"),
    );
  }

  void _unbindConversations() {
    _convSub?.cancel();
    _convSub = null;
  }

  /// 🔄 recalcul du total non-lu
  void _recalculateTotalUnread() {
    final total = _conversations.value.fold<int>(
      0,
      (sum, c) => sum + c.unreadMessagesCount,
    );
    _totalUnread.value = total;
  }

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
      print("Erreur lors du comptage des messages non lus : $e");
      return 0;
    }
  }

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
      print("Erreur création conversation : $e");
      rethrow;
    }
  }

  Stream<List<Message>> getMessages(String conversationId) {
    if (conversationId.isEmpty) {
      print("Erreur : conversationId vide");
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
        data['id'] = doc.id;
        return Message.fromMap(data);
      }).toList();
    });
  }

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String recipientId,
    required String content,
    bool skipPermissionCheck = false,
  }) async {
    try {
      if (!skipPermissionCheck) {
        final canSend = await canSendMessage(
          senderId: senderId,
          recipientId: recipientId,
        );
        if (!canSend) {
          Get.snackbar(
            'Messages indisponibles',
            'L’envoi de messages est désactivé pour cette conversation.',
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }
      }

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

      // ✅ Optionnel : refresh local rapide (sans attendre le prochain snapshot)
      // utile si réseau lent → la liste se met à jour sans délai
      final idx = _conversations.value.indexWhere((c) => c.id == conversationId);
      if (idx != -1) {
        _conversations.value[idx].lastMessage = content;
        _conversations.value[idx].lastMessageDate = DateTime.now();
        _conversations.refresh();
        update();
      }

      final shouldNotify = await _shouldSendNotification(
        recipientId: recipientId,
        conversationId: conversationId,
      );

      if (!shouldNotify) return;

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
      print("Erreur envoi message : $e");
    }
  }

  Future<bool> canSendMessage({
    required String senderId,
    required String recipientId,
  }) async {
    try {
      final senderDoc = await _firestore.collection('users').doc(senderId).get();
      final recipientDoc =
          await _firestore.collection('users').doc(recipientId).get();

      final senderAllow =
          senderDoc.data()?['allowMessages'] as bool? ?? true;
      final recipientAllow =
          recipientDoc.data()?['allowMessages'] as bool? ?? true;

      return senderAllow && recipientAllow;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _shouldSendNotification({
    required String recipientId,
    required String conversationId,
  }) async {
    try {
      final doc = await _firestore.collection('users').doc(recipientId).get();
      if (!doc.exists) return true;

      final data = doc.data() ?? {};
      final activeConvId = data['activeConversationId'] as String?;
      final ts = data['activeAt'] as Timestamp?;
      final activeAt = ts?.toDate();

      if (activeConvId == conversationId && activeAt != null) {
        final isRecent =
            DateTime.now().difference(activeAt) <= _activeWindowTolerance;
        return !isRecent;
      }

      return true;
    } catch (_) {
      return true;
    }
  }

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
      print("Erreur mise à jour message lu : $e");
    }
  }

  Future<void> markMessagesAsRead(String conversationId, String userId) async {
    try {
      final unreadMessages = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('destinataireId', isEqualTo: userId)
          .where('estLu', isEqualTo: false)
          .get();

      if (unreadMessages.docs.isEmpty) {
        // ✅ rien à faire mais on sécurise l’état local
        final index =
            _conversations.value.indexWhere((c) => c.id == conversationId);
        if (index != -1) {
          _conversations.value[index].unreadMessagesCount = 0;
          _recalculateTotalUnread();
          _conversations.refresh();
          update();
        }
        return;
      }

      final batch = _firestore.batch();
      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {'estLu': true});
      }
      await batch.commit();

      // ✅ MAJ locale immédiate (comme ton code, mais avec refresh/UI)
      final index =
          _conversations.value.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        _conversations.value[index].unreadMessagesCount = 0;
        _recalculateTotalUnread();
        _conversations.refresh();
        update();
      }
    } catch (e) {
      print("Erreur mise à jour messages lus : $e");
    }
  }

  /// ✅ marque toutes les conversations comme lues instantanément côté local
  void markAllAsReadLocal() {
    for (var conv in _conversations.value) {
      conv.unreadMessagesCount = 0;
    }
    _recalculateTotalUnread();
    _conversations.refresh();
    update();

    // Optionnel : sync serveur
    Future.microtask(() => markAllAsReadOnServer());
  }

  /// ✅ synchronise toutes les conversations côté serveur
  Future<void> markAllAsReadOnServer() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    for (var conv in _conversations.value) {
      try {
        final unreadMessages = await _firestore
            .collection('conversations')
            .doc(conv.id)
            .collection('messages')
            .where('destinataireId', isEqualTo: userId)
            .where('estLu', isEqualTo: false)
            .get();

        if (unreadMessages.docs.isEmpty) continue;

        final batch = _firestore.batch();
        for (var doc in unreadMessages.docs) {
          batch.update(doc.reference, {'estLu': true});
        }
        await batch.commit();
      } catch (e) {
        print("Erreur markAllAsReadOnServer conv ${conv.id} : $e");
      }
    }
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    try {
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .delete();

      final currentUid = _auth.currentUser?.uid;
      if (currentUid != null) {
        final remaining = await _getUnreadMessageCount(conversationId, currentUid);
        final index =
            _conversations.value.indexWhere((c) => c.id == conversationId);
        if (index != -1) {
          _conversations.value[index].unreadMessagesCount = remaining;
          _recalculateTotalUnread();
          _conversations.refresh();
          update();
        }
      }
    } catch (e) {
      print("Erreur suppression message : $e");
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      final snapshot = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(_firestore.collection('conversations').doc(conversationId));
      await batch.commit();

      // ✅ MAJ locale immédiate pour UI (sinon attendre snapshot)
      _conversations.value.removeWhere((c) => c.id == conversationId);
      _recalculateTotalUnread();
      _conversations.refresh();
      update();
    } catch (e) {
      print("Erreur suppression conversation : $e");
    }
  }
}
