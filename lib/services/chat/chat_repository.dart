import 'package:adfoot/models/message_converstion.dart';
import 'package:adfoot/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRepository {
  ChatRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _conversationsCollection =>
      _firestore.collection('conversations');

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  static String buildConversationId(String uid1, String uid2) {
    final pair = <String>[uid1, uid2]..sort();
    return "${pair.first}__${pair.last}";
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchConversationsForUser(
    String userId,
  ) {
    return _conversationsCollection
        .where('utilisateurIds', arrayContains: userId)
        .snapshots();
  }

  Stream<List<Message>> watchMessages(String conversationId) {
    return _conversationsCollection
        .doc(conversationId)
        .collection('messages')
        .orderBy('dateEnvoi', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return Message.fromMap(data);
          }).toList(growable: false),
        );
  }

  Future<String> createOrGetConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final ids = <String>[currentUserId, otherUserId]..sort();
    final conversationId = buildConversationId(currentUserId, otherUserId);
    final conversationRef = _conversationsCollection.doc(conversationId);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(conversationRef);
      if (snap.exists) return;

      final newConversation = Conversation(
        id: conversationRef.id,
        utilisateur1Id: ids[0],
        utilisateur2Id: ids[1],
        utilisateurIds: ids,
        unreadCountByUser: <String, int>{
          ids[0]: 0,
          ids[1]: 0,
        },
      );

      txn.set(conversationRef, newConversation.toMap());
    });

    return conversationRef.id;
  }

  Future<void> persistMessageAndConversation({
    required String conversationId,
    required Message message,
    required String senderId,
    required String recipientId,
  }) async {
    final messageRef = _conversationsCollection
        .doc(conversationId)
        .collection('messages')
        .doc();
    final conversationRef = _conversationsCollection.doc(conversationId);

    final batch = _firestore.batch();
    batch.set(
      messageRef,
      message.copyWithId(messageRef.id).toMap(),
    );
    batch.set(
      conversationRef,
      <String, dynamic>{
        'lastMessage': message.contenu,
        'lastMessageDate': Timestamp.now(),
        'updatedAt': FieldValue.serverTimestamp(),
        'unreadCountByUser.$recipientId': FieldValue.increment(1),
        'unreadCountByUser.$senderId': 0,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<bool> canSendMessage({
    required String senderId,
    required String recipientId,
  }) async {
    final senderDoc = await _usersCollection.doc(senderId).get();
    final recipientDoc = await _usersCollection.doc(recipientId).get();

    final senderAllow = senderDoc.data()?['allowMessages'] as bool? ?? true;
    final recipientAllow =
        recipientDoc.data()?['allowMessages'] as bool? ?? true;

    return senderAllow && recipientAllow;
  }

  Future<bool> shouldSendNotification({
    required String recipientId,
    required String conversationId,
    required Duration activeWindowTolerance,
  }) async {
    final doc = await _usersCollection.doc(recipientId).get();
    if (!doc.exists) return true;

    final data = doc.data() ?? <String, dynamic>{};
    final activeConvId = data['activeConversationId'] as String?;
    final ts = data['activeAt'] as Timestamp?;
    final activeAt = ts?.toDate();

    if (activeConvId == conversationId && activeAt != null) {
      final isRecent =
          DateTime.now().difference(activeAt) <= activeWindowTolerance;
      return !isRecent;
    }

    return true;
  }

  Future<void> markMessageAsRead({
    required String conversationId,
    required String messageId,
  }) {
    return _conversationsCollection
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update(<String, dynamic>{'estLu': true});
  }

  Future<void> setConversationUnreadToZero({
    required String conversationId,
    required String userId,
  }) {
    return _conversationsCollection.doc(conversationId).set(
      <String, dynamic>{'unreadCountByUser.$userId': 0},
      SetOptions(merge: true),
    );
  }

  Future<void> markMessagesAsRead({
    required String conversationId,
    required String userId,
  }) async {
    final unreadMessages = await _conversationsCollection
        .doc(conversationId)
        .collection('messages')
        .where('destinataireId', isEqualTo: userId)
        .where('estLu', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in unreadMessages.docs) {
      batch.update(doc.reference, <String, dynamic>{'estLu': true});
    }
    batch.set(
      _conversationsCollection.doc(conversationId),
      <String, dynamic>{'unreadCountByUser.$userId': 0},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<Map<String, dynamic>?> fetchConversationData(
      String conversationId) async {
    final doc = await _conversationsCollection.doc(conversationId).get();
    return doc.data();
  }

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) {
    return _conversationsCollection
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  Future<void> deleteConversation(String conversationId) async {
    final snapshot = await _conversationsCollection
        .doc(conversationId)
        .collection('messages')
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_conversationsCollection.doc(conversationId));
    await batch.commit();
  }

  Stream<AppUser?> watchUserById(String uid) {
    return _usersCollection.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      final data = snapshot.data();
      if (data == null) {
        return null;
      }
      return AppUser.fromMap(data);
    });
  }

  Future<void> setActiveConversation({
    required String uid,
    required String? conversationId,
  }) {
    return _usersCollection.doc(uid).update(<String, dynamic>{
      'activeConversationId': conversationId,
      'activeAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> touchActiveConversation(String uid) {
    return _usersCollection.doc(uid).update(<String, dynamic>{
      'activeAt': FieldValue.serverTimestamp(),
    });
  }
}

extension on Message {
  Message copyWithId(String id) {
    return Message(
      id: id,
      expediteurId: expediteurId,
      destinataireId: destinataireId,
      contenu: contenu,
      dateEnvoi: dateEnvoi,
      estLu: estLu,
    );
  }
}
