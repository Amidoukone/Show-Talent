import 'dart:async';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/models/message_converstion.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

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

  int _bindEpoch = 0;
  String? _boundUid;

  @override
  void onInit() {
    super.onInit();

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

  void refreshConversations() {
    final uid = AuthController.instance.currentUid ?? _auth.currentUser?.uid;
    if (uid == null) {
      _resetLocalState();
      _unbindConversations();
      _boundUid = null;
      return;
    }

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
    if (_boundUid == userId && _convSub != null) return;

    _boundUid = userId;
    _unbindConversations();

    final int myEpoch = ++_bindEpoch;

    _convSub = _firestore
        .collection('conversations')
        .where('utilisateurIds', arrayContains: userId)
        .snapshots()
        .listen(
      (snapshot) {
        try {
          if (myEpoch != _bindEpoch) return;

          final items = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;

            final conv = Conversation.fromMap(data);
            final unread = _extractUnreadCount(data, userId);
            conv.unreadMessagesCount = unread;
            conv.unreadCountByUser[userId] = unread;
            return conv;
          }).toList();

          if (myEpoch != _bindEpoch) return;

          _conversations.value = items;
          _recalculateTotalUnread();
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

  int _extractUnreadCount(Map<String, dynamic> data, String userId) {
    final raw = data['unreadCountByUser'];
    if (raw is! Map) return 0;
    final dynamic value = raw[userId];
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  void _recalculateTotalUnread() {
    final total = _conversations.value.fold<int>(
      0,
      (sum, c) => sum + c.unreadMessagesCount,
    );
    _totalUnread.value = total;
  }

  static String _conversationIdFor(String uid1, String uid2) {
    final pair = [uid1, uid2]..sort();
    return "${pair.first}__${pair.last}";
  }

  Future<String> createOrGetConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    if (currentUserId == otherUserId) {
      throw Exception("Impossible de créer une conversation avec soi-même.");
    }

    try {
      final ids = [currentUserId, otherUserId]..sort();
      final conversationId = _conversationIdFor(currentUserId, otherUserId);
      final conversationRef =
          _firestore.collection('conversations').doc(conversationId);

      await _firestore.runTransaction((txn) async {
        final snap = await txn.get(conversationRef);
        if (snap.exists) return;

        final newConversation = Conversation(
          id: conversationRef.id,
          utilisateur1Id: ids[0],
          utilisateur2Id: ids[1],
          utilisateurIds: ids,
          unreadCountByUser: {
            ids[0]: 0,
            ids[1]: 0,
          },
        );

        txn.set(conversationRef, newConversation.toMap());
      });

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

      final conversationRef =
          _firestore.collection('conversations').doc(conversationId);
      final batch = _firestore.batch();
      batch.set(messageRef, message.toMap());
      batch.set(
        conversationRef,
        {
          'lastMessage': content,
          'lastMessageDate': Timestamp.now(),
          'updatedAt': FieldValue.serverTimestamp(),
          'unreadCountByUser.$recipientId': FieldValue.increment(1),
          'unreadCountByUser.$senderId': 0,
        },
        SetOptions(merge: true),
      );
      await batch.commit();

      final idx =
          _conversations.value.indexWhere((c) => c.id == conversationId);
      if (idx != -1) {
        _conversations.value[idx].lastMessage = content;
        _conversations.value[idx].lastMessageDate = DateTime.now();
        _conversations.value[idx].unreadCountByUser[senderId] = 0;
        _conversations.value[idx].unreadMessagesCount = _conversations
                .value[idx].unreadCountByUser[_boundUid ?? senderId] ??
            0;
        _recalculateTotalUnread();
        _conversations.refresh();
        update();
      }

      final shouldNotify = await _shouldSendNotification(
        recipientId: recipientId,
        conversationId: conversationId,
      );

      if (!shouldNotify) return;

      await PushNotificationService.sendNotification(
        title: 'Nouveau message',
        body: content,
        recipientUid: recipientId,
        contextType: 'message',
        contextData: conversationId,
      );
    } catch (e) {
      print("Erreur envoi message : $e");
    }
  }

  Future<bool> canSendMessage({
    required String senderId,
    required String recipientId,
  }) async {
    try {
      final senderDoc =
          await _firestore.collection('users').doc(senderId).get();
      final recipientDoc =
          await _firestore.collection('users').doc(recipientId).get();

      final senderAllow = senderDoc.data()?['allowMessages'] as bool? ?? true;
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

      final userId = _auth.currentUser?.uid;
      if (userId != null) {
        await _setConversationUnreadToZero(conversationId, userId);
      }
    } catch (e) {
      print("Erreur mise à jour message lu : $e");
    }
  }

  Future<void> _setConversationUnreadToZero(
      String conversationId, String userId) async {
    await _firestore.collection('conversations').doc(conversationId).set(
      {'unreadCountByUser.$userId': 0},
      SetOptions(merge: true),
    );
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

      final batch = _firestore.batch();
      for (final doc in unreadMessages.docs) {
        batch.update(doc.reference, {'estLu': true});
      }
      batch.set(
        _firestore.collection('conversations').doc(conversationId),
        {'unreadCountByUser.$userId': 0},
        SetOptions(merge: true),
      );
      await batch.commit();

      final index =
          _conversations.value.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        _conversations.value[index].unreadCountByUser[userId] = 0;
        _conversations.value[index].unreadMessagesCount = 0;
        _recalculateTotalUnread();
        _conversations.refresh();
        update();
      }
    } catch (e) {
      print("Erreur mise à jour messages lus : $e");
    }
  }

  void markAllAsReadLocal() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    for (final conv in _conversations.value) {
      conv.unreadCountByUser[uid] = 0;
      conv.unreadMessagesCount = 0;
    }
    _recalculateTotalUnread();
    _conversations.refresh();
    update();

    Future.microtask(() => markAllAsReadOnServer());
  }

  Future<void> markAllAsReadOnServer() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    for (final conv in _conversations.value) {
      try {
        final unreadMessages = await _firestore
            .collection('conversations')
            .doc(conv.id)
            .collection('messages')
            .where('destinataireId', isEqualTo: userId)
            .where('estLu', isEqualTo: false)
            .get();

        final batch = _firestore.batch();
        for (final doc in unreadMessages.docs) {
          batch.update(doc.reference, {'estLu': true});
        }
        batch.set(
          _firestore.collection('conversations').doc(conv.id),
          {'unreadCountByUser.$userId': 0},
          SetOptions(merge: true),
        );
        await batch.commit();
      } catch (e) {
        print("Erreur markAllAsReadOnServer conv ${conv.id} : $e");
      }
    }
  }

  Future<void> _syncUnreadFromConversation(
      String conversationId, String userId) async {
    final convDoc =
        await _firestore.collection('conversations').doc(conversationId).get();
    if (!convDoc.exists) return;

    final data = convDoc.data() ?? <String, dynamic>{};
    final unread = _extractUnreadCount(data, userId);
    final index =
        _conversations.value.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations.value[index].unreadCountByUser[userId] = unread;
      _conversations.value[index].unreadMessagesCount = unread;
      _recalculateTotalUnread();
      _conversations.refresh();
      update();
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
        await _syncUnreadFromConversation(conversationId, currentUid);
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
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(_firestore.collection('conversations').doc(conversationId));
      await batch.commit();

      _conversations.value.removeWhere((c) => c.id == conversationId);
      _recalculateTotalUnread();
      _conversations.refresh();
      update();
    } catch (e) {
      print("Erreur suppression conversation : $e");
    }
  }
}
