import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/models/message_converstion.dart';
import '../controller/chat_controller.dart';
import '../models/user.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final AppUser otherUser;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ChatController chatController = Get.find<ChatController>();
  final TextEditingController messageController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _listScroll = ScrollController();

  late final Stream<List<Message>> _messagesStream;

  Timer? _heartbeatTimer;
  DateTime? _lastTouchAt;
  static const Duration _heartbeatPeriod = Duration(seconds: 12);
  static const Duration _touchThrottle = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messagesStream = chatController.getMessages(widget.conversationId);

    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus) {
        _scrollToBottom(delay: const Duration(milliseconds: 150));
        _throttledTouchActiveAt();
      }
    });

    messageController.addListener(_throttledTouchActiveAt);

    _enterActiveConversation();
    _startHeartbeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopHeartbeat();
    _leaveActiveConversation();
    _inputFocus.dispose();
    _listScroll.dispose();
    messageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _leaveActiveConversation();
      _stopHeartbeat();
    } else if (state == AppLifecycleState.resumed) {
      _enterActiveConversation();
      _startHeartbeat();
      _throttledTouchActiveAt();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthController.instance.user;
    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Erreur")),
        body: const Center(child: Text("Utilisateur non connecté.")),
      );
    }

    final otherUser = widget.otherUser;

    return PopScope(
      // ✅ Correction : onPopInvoked → onPopInvokedWithResult (Flutter 3.22+)
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return; // si le pop est déjà géré, ne rien faire
        await _leaveActiveConversation();
        if (mounted) Get.back(result: result);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: otherUser.photoProfil.isNotEmpty
                    ? NetworkImage(otherUser.photoProfil)
                    : null,
                child: otherUser.photoProfil.isEmpty
                    ? Text(
                        otherUser.nom.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.black),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  otherUser.nom,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Message>>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text("Aucun message."));
                    }

                    final messages = snapshot.data!;
                    _markMessagesAsRead(messages, currentUser.uid);

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollToBottom();
                    });

                    return ListView.builder(
                      controller: _listScroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isSentByUser =
                            message.expediteurId == currentUser.uid;

                        return GestureDetector(
                          onLongPress: () {
                            if (isSentByUser) {
                              _confirmDeleteMessage(message);
                            }
                          },
                          child: Align(
                            alignment: isSentByUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                vertical: 5,
                                horizontal: 10,
                              ),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isSentByUser
                                    ? const Color(0xFFDBF4D3)
                                    : const Color(0xFFD2F2F0),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: isSentByUser
                                      ? const Radius.circular(12)
                                      : Radius.zero,
                                  bottomRight: isSentByUser
                                      ? Radius.zero
                                      : const Radius.circular(12),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.contenu,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatTime(message.dateEnvoi),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (isSentByUser)
                                        Icon(
                                          _getMessageIcon(message),
                                          size: 16,
                                          color: Colors.grey[700],
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              MessageInputBar(
                controller: messageController,
                focusNode: _inputFocus,
                onSend: () => _sendMessage(currentUser.uid, otherUser.uid),
                onUserActivity: _throttledTouchActiveAt,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteMessage(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer ce message"),
        content: const Text("Voulez-vous vraiment supprimer ce message ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await chatController.deleteMessage(
                    widget.conversationId, message.id);
                Get.snackbar(
                  "Message supprimé",
                  "",
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.grey.shade800,
                  colorText: Colors.white,
                );
              } catch (e) {
                Get.snackbar(
                  "Erreur",
                  "Échec de la suppression du message : $e",
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            },
            child: const Text(
              "Supprimer",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enterActiveConversation() async {
    final user = AuthController.instance.user;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'activeConversationId': widget.conversationId,
        'activeAt': FieldValue.serverTimestamp(),
      });
      _lastTouchAt = DateTime.now();
    } catch (_) {}
  }

  Future<void> _leaveActiveConversation() async {
    final user = AuthController.instance.user;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'activeConversationId': null,
        'activeAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(_heartbeatPeriod, (_) => _touchActiveAt());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _throttledTouchActiveAt() {
    final now = DateTime.now();
    if (_lastTouchAt == null ||
        now.difference(_lastTouchAt!) >= _touchThrottle) {
      _lastTouchAt = now;
      _touchActiveAt();
    }
  }

  Future<void> _touchActiveAt() async {
    final user = AuthController.instance.user;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'activeAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  void _sendMessage(String senderId, String recipientId) {
    final content = messageController.text.trim();
    if (content.isEmpty) return;

    chatController.sendMessage(
      conversationId: widget.conversationId,
      senderId: senderId,
      recipientId: recipientId,
      content: content,
    );

    messageController.clear();
    _scrollToBottom(delay: const Duration(milliseconds: 120));
    _throttledTouchActiveAt();
  }

  void _scrollToBottom({Duration delay = Duration.zero}) {
    Future.delayed(delay, () {
      if (!_listScroll.hasClients) return;
      _listScroll.animateTo(
        0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _markMessagesAsRead(List<Message> messages, String currentUserId) {
    for (var message in messages) {
      if (!message.estLu && message.destinataireId == currentUserId) {
        chatController.markMessageAsRead(
          conversationId: widget.conversationId,
          messageId: message.id,
        );
      }
    }
  }

  IconData _getMessageIcon(Message message) {
    return message.estLu ? Icons.done_all : Icons.done;
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    if (now.difference(dateTime).inDays == 0) {
      final h = dateTime.hour.toString().padLeft(2, '0');
      final m = dateTime.minute.toString().padLeft(2, '0');
      return "$h:$m";
    } else {
      final d = dateTime.day.toString().padLeft(2, '0');
      final mo = dateTime.month.toString().padLeft(2, '0');
      final y = dateTime.year.toString();
      return "$d/$mo/$y";
    }
  }
}

/// Widget d’entrée de message
class MessageInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onUserActivity;

  const MessageInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onUserActivity,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        bottom: bottom > 0 ? bottom + 8 : 8,
        top: 6,
      ),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 48,
                maxHeight: 140,
              ),
              child: Scrollbar(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 1,
                      maxLines: null,
                      onChanged: (_) => onUserActivity(),
                      onTap: onUserActivity,
                      decoration: InputDecoration(
                        hintText: "Tapez un message…",
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final canSend = value.text.trim().isNotEmpty;
              return CircleAvatar(
                backgroundColor: canSend
                    ? const Color.fromARGB(255, 3, 121, 9)
                    : Colors.grey.shade400,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: canSend ? onSend : null,
                  tooltip: 'Envoyer',
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
