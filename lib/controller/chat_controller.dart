import 'dart:async';

import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/message_converstion.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/chat/chat_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

typedef ChatNotificationSender = Future<void> Function({
  required String title,
  required String body,
  required String recipientUid,
  required String contextType,
  required String contextData,
});

class ChatFlowException implements Exception {
  const ChatFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChatController extends GetxController {
  static const Duration _activeWindowTolerance = Duration(seconds: 25);

  ChatController({
    AuthSessionService? authSessionService,
    ChatRepository? chatRepository,
    ChatNotificationSender? notificationSender,
    Future<void> Function()? protectedAccessDeniedHandler,
    String? Function()? currentUidResolver,
  })  : _authSessionService = authSessionService ?? AuthSessionService(),
        _chatRepository = chatRepository ?? ChatRepository(),
        _notificationSender =
            notificationSender ?? PushNotificationService.sendNotification,
        _protectedAccessDeniedHandler = protectedAccessDeniedHandler,
        _currentUidResolver = currentUidResolver;

  final AuthSessionService _authSessionService;
  final ChatRepository _chatRepository;
  final ChatNotificationSender _notificationSender;
  final Future<void> Function()? _protectedAccessDeniedHandler;
  final String? Function()? _currentUidResolver;

  final Rx<List<Conversation>> _conversations =
      Rx<List<Conversation>>(<Conversation>[]);
  List<Conversation> get conversations => _conversations.value;

  final RxInt _totalUnread = 0.obs;
  int get totalUnread => _totalUnread.value;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _convSub;

  int _bindEpoch = 0;
  String? _boundUid;

  bool _isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  String? _resolvedCurrentUid() {
    final injected = _currentUidResolver?.call()?.trim();
    if (injected != null && injected.isNotEmpty) {
      return injected;
    }

    if (Get.isRegistered<AuthController>()) {
      final authController = Get.find<AuthController>();
      final currentUid = authController.currentUid?.trim();
      if (currentUid != null && currentUid.isNotEmpty) {
        return currentUid;
      }
    }

    return _authSessionService.currentUser?.uid;
  }

  Future<void> _handleProtectedAccessDenied() async {
    final protectedAccessDeniedHandler = _protectedAccessDeniedHandler;
    if (protectedAccessDeniedHandler != null) {
      await protectedAccessDeniedHandler();
      return;
    }

    if (!Get.isRegistered<UserController>()) {
      return;
    }

    await Get.find<UserController>().handleProtectedAccessDenied(
      fallbackTitle: 'Accès indisponible',
      fallbackMessage:
          'Votre session a été fermée pour protéger votre compte. Veuillez vous reconnecter.',
    );
  }

  @override
  void onInit() {
    super.onInit();

    _authSub = _authSessionService.idTokenChanges().listen(
      (user) {
        if (user == null) {
          _resetLocalState();
          _unbindConversations();
          _boundUid = null;
          return;
        }
        _bindConversationsFor(user.uid);
      },
      onError: (error) =>
          debugPrint("ChatController auth listen error: $error"),
    );

    final uid = _resolvedCurrentUid();
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
    final uid = _resolvedCurrentUid();
    if (uid == null) {
      _resetLocalState();
      _unbindConversations();
      _boundUid = null;
      return;
    }

    if (_boundUid == uid && _convSub != null) {
      _unbindConversations();
      _boundUid = null;
      _bindConversationsFor(uid);
      return;
    }

    _bindConversationsFor(uid);
  }

  Stream<AppUser?> watchUserById(String uid) {
    return _chatRepository.watchUserById(uid);
  }

  Stream<Conversation?> watchConversationById(String conversationId) {
    return _chatRepository.watchConversationById(conversationId);
  }

  Future<void> setActiveConversation({
    required String uid,
    String? conversationId,
  }) {
    return _chatRepository.setActiveConversation(
      uid: uid,
      conversationId: conversationId,
    );
  }

  Future<void> touchActiveConversation(String uid) {
    return _chatRepository.touchActiveConversation(uid);
  }

  void _resetLocalState() {
    _conversations.value = <Conversation>[];
    _totalUnread.value = 0;
    _conversations.refresh();
    update();
  }

  void _bindConversationsFor(String userId) {
    if (_boundUid == userId && _convSub != null) {
      return;
    }

    _boundUid = userId;
    _unbindConversations();

    final myEpoch = ++_bindEpoch;

    _convSub = _chatRepository.watchConversationsForUser(userId).listen(
      (snapshot) {
        try {
          if (myEpoch != _bindEpoch) {
            return;
          }

          final items = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;

            final conv = Conversation.fromMap(data);
            final unread = _extractUnreadCount(data, userId);
            conv.unreadMessagesCount = unread;
            conv.unreadCountByUser[userId] = unread;
            return conv;
          }).toList();

          if (myEpoch != _bindEpoch) {
            return;
          }

          _conversations.value = items;
          _recalculateTotalUnread();
          _conversations.refresh();
          update();
        } catch (error) {
          debugPrint("Erreur lors du chargement des conversations : $error");
        }
      },
      onError: (error) {
        debugPrint("Erreur ecoute conversations : $error");
        if (_isPermissionDenied(error)) {
          _resetLocalState();
          unawaited(_handleProtectedAccessDenied());
        }
      },
    );
  }

  void _unbindConversations() {
    _convSub?.cancel();
    _convSub = null;
  }

  int _extractUnreadCount(Map<String, dynamic> data, String userId) {
    final raw = data['unreadCountByUser'];
    if (raw is! Map) {
      return 0;
    }
    final value = raw[userId];
    if (value is int) {
      return value;
    }
    return int.tryParse('$value') ?? 0;
  }

  void _recalculateTotalUnread() {
    final total = _conversations.value.fold<int>(
      0,
      (totalUnread, c) => totalUnread + c.unreadMessagesCount,
    );
    _totalUnread.value = total;
  }

  Future<String> createOrGetConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    if (currentUserId.trim().isEmpty || otherUserId.trim().isEmpty) {
      throw const ChatFlowException(
        'Identifiants de conversation invalides.',
      );
    }

    if (currentUserId == otherUserId) {
      throw const ChatFlowException(
        'Impossible de créer une conversation avec soi-même.',
      );
    }

    try {
      return await _chatRepository.createOrGetConversation(
        currentUserId: currentUserId,
        otherUserId: otherUserId,
      );
    } on FirebaseException catch (error) {
      debugPrint("Erreur creation conversation firebase : $error");
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        throw const ChatFlowException(
          'Votre session a été fermée. Veuillez vous reconnecter.',
        );
      }
      throw const ChatFlowException(
        'Impossible de démarrer la conversation pour le moment.',
      );
    } catch (error) {
      debugPrint("Erreur creation conversation : $error");
      throw const ChatFlowException(
        'Impossible de démarrer la conversation pour le moment.',
      );
    }
  }

  Future<String?> findExistingConversationId({
    required String currentUserId,
    required String otherUserId,
  }) async {
    try {
      return await _chatRepository.findExistingConversationId(
        currentUserId: currentUserId,
        otherUserId: otherUserId,
      );
    } on FirebaseException catch (error) {
      debugPrint("Erreur recherche conversation firebase : $error");
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
      return null;
    } catch (error) {
      debugPrint("Erreur recherche conversation : $error");
      return null;
    }
  }

  Future<GuidedConversationStartResult> startGuidedConversation({
    required AppUser currentUser,
    required AppUser otherUser,
    required ContactContext context,
    required String contactReason,
    required String introMessage,
  }) async {
    try {
      return await _chatRepository.startGuidedConversation(
        currentUser: currentUser,
        otherUser: otherUser,
        context: context,
        contactReason: contactReason,
        introMessage: introMessage,
      );
    } on FirebaseException catch (error) {
      debugPrint("Erreur creation contact guide firebase : $error");
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        throw const ChatFlowException(
          'Votre session a été fermée. Veuillez vous reconnecter.',
        );
      }
      throw const ChatFlowException(
        'Impossible de lancer ce premier contact pour le moment.',
      );
    } catch (error) {
      debugPrint("Erreur creation contact guide : $error");
      throw const ChatFlowException(
        'Impossible de lancer ce premier contact pour le moment.',
      );
    }
  }

  Stream<List<Message>> getMessages(String conversationId) {
    if (conversationId.isEmpty) {
      debugPrint("Erreur : conversationId vide");
      return const Stream<List<Message>>.empty();
    }

    return _chatRepository.watchMessages(conversationId);
  }

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String recipientId,
    required String content,
    bool skipPermissionCheck = false,
  }) async {
    final normalizedConversationId = conversationId.trim();
    final normalizedSenderId = senderId.trim();
    final normalizedRecipientId = recipientId.trim();
    final normalizedContent = content.trim();

    if (normalizedConversationId.isEmpty ||
        normalizedSenderId.isEmpty ||
        normalizedRecipientId.isEmpty) {
      throw const ChatFlowException(
        'Session de messagerie invalide. Merci de réessayer.',
      );
    }

    if (normalizedContent.isEmpty) {
      throw const ChatFlowException(
        'Le message est vide.',
      );
    }

    if (normalizedContent.length > 2000) {
      throw const ChatFlowException(
        'Le message dépasse la limite autorisée (2000 caractères).',
      );
    }

    try {
      if (!skipPermissionCheck) {
        final canSend = await canSendMessage(
          senderId: normalizedSenderId,
          recipientId: normalizedRecipientId,
        );
        if (!canSend) {
          throw const ChatFlowException(
            'L\'envoi de messages est désactivé pour cette conversation.',
          );
        }
      }

      final message = Message(
        id: '',
        expediteurId: normalizedSenderId,
        destinataireId: normalizedRecipientId,
        contenu: normalizedContent,
        dateEnvoi: DateTime.now(),
        estLu: false,
      );

      await _chatRepository.persistMessageAndConversation(
        conversationId: normalizedConversationId,
        message: message,
        senderId: normalizedSenderId,
        recipientId: normalizedRecipientId,
      );

      final idx = _conversations.value
          .indexWhere((c) => c.id == normalizedConversationId);
      if (idx != -1) {
        _conversations.value[idx].lastMessage = normalizedContent;
        _conversations.value[idx].lastMessageDate = DateTime.now();
        _conversations.value[idx].unreadCountByUser[normalizedSenderId] = 0;
        _conversations.value[idx].unreadMessagesCount = _conversations
                .value[idx]
                .unreadCountByUser[_boundUid ?? normalizedSenderId] ??
            0;
        _recalculateTotalUnread();
        _conversations.refresh();
        update();
      }

      try {
        final shouldNotify = await _chatRepository.shouldSendNotification(
          recipientId: normalizedRecipientId,
          conversationId: normalizedConversationId,
          activeWindowTolerance: _activeWindowTolerance,
        );
        if (!shouldNotify) {
          return;
        }

        await _notificationSender(
          title: 'Nouveau message',
          body: normalizedContent,
          recipientUid: normalizedRecipientId,
          contextType: 'message',
          contextData: normalizedConversationId,
        );
      } catch (notificationError, notificationStackTrace) {
        debugPrint(
          'Notification message non bloquante: '
          '$notificationError\n$notificationStackTrace',
        );
      }
    } on ChatFlowException {
      rethrow;
    } on FirebaseException catch (error) {
      debugPrint(
          "Erreur envoi message firebase : ${error.code} ${error.message}");
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        throw const ChatFlowException(
          'Votre session a été fermée. Veuillez vous reconnecter.',
        );
      }
      throw const ChatFlowException(
        'Envoi impossible pour le moment. Vérifiez votre connexion.',
      );
    } catch (error) {
      debugPrint("Erreur envoi message : $error");
      throw const ChatFlowException(
        'Envoi impossible pour le moment. Merci de réessayer.',
      );
    }
  }

  Future<bool> canSendMessage({
    required String senderId,
    required String recipientId,
  }) async {
    try {
      return await _chatRepository.canSendMessage(
        senderId: senderId,
        recipientId: recipientId,
      );
    } on FirebaseException catch (error) {
      debugPrint("Erreur vérification messagerie firebase : $error");
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markMessageAsRead({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      await _chatRepository.markMessageAsRead(
        conversationId: conversationId,
        messageId: messageId,
      );

      final userId = _authSessionService.currentUser?.uid;
      if (userId != null) {
        await _chatRepository.setConversationUnreadToZero(
          conversationId: conversationId,
          userId: userId,
        );
      }
    } catch (error) {
      debugPrint("Erreur mise a jour message lu : $error");
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
    }
  }

  Future<void> markMessagesAsRead(String conversationId, String userId) async {
    try {
      await _chatRepository.markMessagesAsRead(
        conversationId: conversationId,
        userId: userId,
      );

      final index =
          _conversations.value.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        _conversations.value[index].unreadCountByUser[userId] = 0;
        _conversations.value[index].unreadMessagesCount = 0;
        _recalculateTotalUnread();
        _conversations.refresh();
        update();
      }
    } catch (error) {
      debugPrint("Erreur mise a jour messages lus : $error");
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
    }
  }

  void markAllAsReadLocal() {
    final uid = _authSessionService.currentUser?.uid;
    if (uid == null) {
      return;
    }

    for (final conv in _conversations.value) {
      conv.unreadCountByUser[uid] = 0;
      conv.unreadMessagesCount = 0;
    }
    _recalculateTotalUnread();
    _conversations.refresh();
    update();

    Future.microtask(markAllAsReadOnServer);
  }

  Future<void> markAllAsReadOnServer() async {
    final userId = _authSessionService.currentUser?.uid;
    if (userId == null) {
      return;
    }

    for (final conv in _conversations.value) {
      try {
        await _chatRepository.markMessagesAsRead(
          conversationId: conv.id,
          userId: userId,
        );
      } catch (error) {
        debugPrint("Erreur markAllAsReadOnServer conv ${conv.id} : $error");
        if (_isPermissionDenied(error)) {
          unawaited(_handleProtectedAccessDenied());
          return;
        }
      }
    }
  }

  Future<void> _syncUnreadFromConversation(
    String conversationId,
    String userId,
  ) async {
    final data = await _chatRepository.fetchConversationData(conversationId);
    if (data == null) {
      return;
    }

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
      await _chatRepository.deleteMessage(
        conversationId: conversationId,
        messageId: messageId,
      );

      final currentUid = _authSessionService.currentUser?.uid;
      if (currentUid != null) {
        await _syncUnreadFromConversation(conversationId, currentUid);
      }
    } catch (error) {
      debugPrint("Erreur suppression message : $error");
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      await _chatRepository.deleteConversation(conversationId);
      _conversations.value.removeWhere((c) => c.id == conversationId);
      _recalculateTotalUnread();
      _conversations.refresh();
      update();
    } catch (error) {
      debugPrint("Erreur suppression conversation : $error");
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
    }
  }
}
