import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/models/message_converstion.dart';
import '../controller/chat_controller.dart';
import '../models/user.dart';

/// ------------------------------
/// Mini design system Chat (simple, moderne, safe)
/// - Zéro impact logique : uniquement UI
/// - Adapté aux réseaux lents (pas de widgets lourds)
/// ------------------------------
class ChatUi {
  // Spacing
  static const double pagePad = 12;
  static const double bubblePadH = 12;
  static const double bubblePadV = 10;
  static const double bubbleRadius = 18;
  static const double bubbleMaxWidthFactor = 0.78;
  static const double avatarRadius = 18;

  // Text sizes
  static const double msgFont = 15.5;
  static const double metaFont = 11.5;

  // Colors (cohérent avec ton thème brand teal)
  // Astuce: on s'appuie sur ColorScheme quand possible (dark mode friendly),
  // mais on garde des fallback stables.
  static Color sentBubble(ColorScheme cs) =>
      cs.secondaryContainer; // accentDark / teal-ish
  static Color receivedBubble(ColorScheme cs) =>
      cs.surfaceContainerHighest; // gris clair moderne

  static Color sentText(ColorScheme cs) => cs.onSecondaryContainer;
  static Color receivedText(ColorScheme cs) => cs.onSurface;

  static Color meta(ColorScheme cs) => cs.onSurface.withValues(alpha: 0.55);

  static const Color onlineDot = Color(0xFF2DBA8C);
}

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

  // ✅ Petit cache UI : regroupe l'affichage des dates
  String? _lastDateHeaderKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _messagesStream = chatController.getMessages(widget.conversationId);

    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus) {
        _scrollToBottom(delay: const Duration(milliseconds: 120));
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveActiveConversation();
        if (mounted) Get.back(result: result);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              const SizedBox(width: 8),
              _ChatHeaderAvatar(user: otherUser),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      otherUser.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: ChatUi.onlineDot.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "En ligne", // UI seulement (ne change pas ta logique)
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: DecoratedBox(
          // ✅ fond subtil (moderne) sans assets
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.surface,
                cs.surfaceContainerLow,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<Message>>(
                    stream: _messagesStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final messages = snapshot.data ?? const <Message>[];

                      if (messages.isEmpty) {
                        return _EmptyChatState(
                          otherUserName: otherUser.nom,
                        );
                      }

                      // ✅ Marque comme lu (logique existante conservée)
                      _markMessagesAsRead(messages, currentUser.uid);

                      // ✅ Scroll au bas après frame (comme avant)
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToBottom();
                      });

                      // reset date header state each build for correct grouping
                      _lastDateHeaderKey = null;

                      return ListView.builder(
                        controller: _listScroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(
                          ChatUi.pagePad,
                          10,
                          ChatUi.pagePad,
                          10,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isSentByUser =
                              message.expediteurId == currentUser.uid;

                          // ✅ Date grouping (UI only) - fonctionne avec reverse:true
                          // On compare avec le message suivant (plus ancien visuellement)
                          final String dateKey = _dayKey(message.dateEnvoi);
                          bool showDateHeader = false;

                          if (_lastDateHeaderKey != dateKey) {
                            showDateHeader = true;
                            _lastDateHeaderKey = dateKey;
                          }

                          return Column(
                            children: [
                              if (showDateHeader)
                                _DatePill(
                                    label: _formatDayLabel(message.dateEnvoi)),
                              _MessageBubble(
                                cs: cs,
                                isMe: isSentByUser,
                                message: message,
                                onLongPress: () {
                                  if (isSentByUser) {
                                    _confirmDeleteMessage(message);
                                  }
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),

                // ✅ Input bar modernisée + cohérente avec ConversationsScreen
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
      ),
    );
  }

  // ------------------------------
  // Delete message
  // ------------------------------
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
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ------------------------------
  // Active conversation (notif throttle) - logique existante conservée
  // ------------------------------
  Future<void> _enterActiveConversation() async {
    final user = AuthController.instance.user;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'activeConversationId': null,
        'activeAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatPeriod, (_) => _touchActiveAt());
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

  // ------------------------------
  // Send + scroll - logique existante conservée
  // ------------------------------
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
    _scrollToBottom(delay: const Duration(milliseconds: 110));
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

  // ------------------------------
  // Formatting helpers (UI only)
  // ------------------------------
  String _dayKey(DateTime dt) => "${dt.year}-${dt.month}-${dt.day}";

  String _formatDayLabel(DateTime dateTime) {
    final now = DateTime.now();
    final todayKey = _dayKey(now);
    final dKey = _dayKey(dateTime);

    if (dKey == todayKey) return "Aujourd’hui";

    final yesterday = now.subtract(const Duration(days: 1));
    if (_dayKey(yesterday) == dKey) return "Hier";

    final d = dateTime.day.toString().padLeft(2, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final y = dateTime.year.toString();
    return "$d/$m/$y";
  }

  // ------------------------------
  // UI components
  // ------------------------------

  Widget _DatePill({required String label}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _EmptyChatState({required String otherUserName}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: cs.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              "Aucun message",
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Commence la discussion avec $otherUserName.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.65),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar header modernisé (UI-only)
class _ChatHeaderAvatar extends StatelessWidget {
  final AppUser user;

  const _ChatHeaderAvatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallbackBg = theme.colorScheme.surfaceContainerHighest;

    final initial =
        user.nom.trim().isNotEmpty ? user.nom.trim()[0].toUpperCase() : "?";

    return Stack(
      children: [
        CircleAvatar(
          radius: ChatUi.avatarRadius,
          backgroundColor: fallbackBg,
          backgroundImage: user.photoProfil.isNotEmpty
              ? NetworkImage(user.photoProfil)
              : null,
          child: user.photoProfil.isEmpty
              ? Text(
                  initial,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                )
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: ChatUi.onlineDot,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        )
      ],
    );
  }
}

/// Bulle message moderne, cohérente (UI-only) + long-press delete conservé
class _MessageBubble extends StatelessWidget {
  final ColorScheme cs;
  final bool isMe;
  final Message message;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.cs,
    required this.isMe,
    required this.message,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final maxW =
        MediaQuery.of(context).size.width * ChatUi.bubbleMaxWidthFactor;

    final bubbleColor =
        isMe ? ChatUi.sentBubble(cs) : ChatUi.receivedBubble(cs);
    final textColor = isMe ? ChatUi.sentText(cs) : ChatUi.receivedText(cs);
    final metaColor = ChatUi.meta(cs);

    final radius = Radius.circular(ChatUi.bubbleRadius);

    // Forme moderne : légèrement différente pour moi vs autre
    final borderRadius = BorderRadius.only(
      topLeft: radius,
      topRight: radius,
      bottomLeft: isMe ? radius : const Radius.circular(6),
      bottomRight: isMe ? const Radius.circular(6) : radius,
    );

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isMe ? 54 : 0,
        right: isMe ? 0 : 54,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ChatUi.bubblePadH,
                vertical: ChatUi.bubblePadV,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: borderRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.contenu,
                    style: TextStyle(
                      fontSize: ChatUi.msgFont,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.dateEnvoi),
                        style: TextStyle(
                          fontSize: ChatUi.metaFont,
                          color: metaColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Icon(
                          message.estLu ? Icons.done_all : Icons.done,
                          size: 16,
                          color: metaColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }
}

/// Widget d’entrée de message modernisé + cohérent (UI-only)
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 10,
          right: 10,
          bottom: bottom > 0 ? bottom + 8 : 10,
          top: 8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.7),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    maxHeight: 140,
                  ),
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
                          hintStyle: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w600,
                          ),
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final canSend = value.text.trim().isNotEmpty;

                return AnimatedScale(
                  duration: const Duration(milliseconds: 120),
                  scale: canSend ? 1.0 : 0.98,
                  child: Material(
                    color: canSend
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.25),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canSend ? onSend : null,
                      child: const SizedBox(
                        width: 46,
                        height: 46,
                        child: Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
