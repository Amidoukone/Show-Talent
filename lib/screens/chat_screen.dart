import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/models/message_converstion.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import '../controller/chat_controller.dart';
import '../models/user.dart';
import '../widgets/ad_dialogs.dart';
import '../widgets/ad_feedback.dart';
import '../widgets/ad_state_panel.dart';

/// ------------------------------
/// Mini design system Chat (simple, moderne, safe)
/// - Zéro impact logique : uniquement UI
/// - Adapté aux réseaux lents (pas de widgets lourds)
/// ------------------------------
class ChatUi {
  // Spacing
  static const double pagePad = 14;
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
      cs.primaryContainer; // accent brand / teal-ish
  static Color receivedBubble(ColorScheme cs) =>
      cs.surfaceContainerHigh; // gris clair moderne

  static Color sentText(ColorScheme cs) => cs.onPrimaryContainer;
  static Color receivedText(ColorScheme cs) => cs.onSurface;

  static Color meta(ColorScheme cs) => cs.onSurface.withValues(alpha: 0.62);

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
  final UserController _userController = Get.find<UserController>();
  final AuthSessionService _authSessionService = AuthSessionService();
  final TextEditingController messageController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _listScroll = ScrollController();

  late final Stream<List<Message>> _messagesStream;
  late final Stream<Conversation?> _conversationStream;
  late AppUser _otherUser;
  StreamSubscription<AppUser?>? _otherUserSub;

  Timer? _heartbeatTimer;
  DateTime? _lastTouchAt;
  static const Duration _heartbeatPeriod = Duration(seconds: 12);
  static const Duration _touchThrottle = Duration(seconds: 3);
  DateTime? _lastReadSyncAt;
  bool _readSyncInFlight = false;
  static const Duration _readSyncThrottle = Duration(seconds: 2);
  bool _isSendingMessage = false;

  // ✅ Petit cache UI : regroupe l'affichage des dates
  String? _lastDateHeaderKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _messagesStream = chatController.getMessages(widget.conversationId);
    _conversationStream = chatController.watchConversationById(
      widget.conversationId,
    );
    _otherUser = widget.otherUser;
    _startOtherUserListener();

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
    _otherUserSub?.cancel();
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

  Future<void> _handleBackNavigation({Object? result}) async {
    await _leaveActiveConversation();
    if (mounted) Get.back(result: result);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _resolvedCurrentUser;
    if (currentUser == null && _authSessionService.currentUser != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chargement')),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Erreur')),
        body: const Center(
          child: AdStatePanel.error(
            title: 'Session invalide',
            message: 'Utilisateur non connecte.',
          ),
        ),
      );
    }

    final otherUser = _otherUser;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canMessage = currentUser.allowMessages && otherUser.allowMessages;
    final disabledHint =
        (!currentUser.allowMessages && !otherUser.allowMessages)
            ? 'Les messages sont désactivés pour vous deux.'
            : currentUser.allowMessages
                ? 'Cet utilisateur a désactivé les messages.'
                : 'Vous avez désactivé les messages.';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation(result: result);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => _handleBackNavigation(),
          ),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.surface,
                  cs.surfaceContainerHighest.withValues(alpha: 0.9),
                ],
              ),
            ),
          ),
          titleSpacing: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(
              height: 1,
              thickness: 1,
              color: cs.outline.withValues(alpha: 0.35),
            ),
          ),
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
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
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
                          "Discussion en direct", // UI seulement (ne change pas ta logique)
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w700,
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
                cs.surfaceContainerHigh,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                StreamBuilder<Conversation?>(
                  stream: _conversationStream,
                  builder: (context, snapshot) {
                    return _buildGuidedContextBanner(snapshot.data);
                  },
                ),
                Expanded(
                  child: StreamBuilder<List<Message>>(
                    stream: _messagesStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: AdStatePanel.loading(
                            title: 'Chargement des messages',
                            message: 'Synchronisation de la conversation.',
                          ),
                        );
                      }

                      final messages = snapshot.data ?? const <Message>[];

                      if (messages.isEmpty) {
                        return _emptyChatState(
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
                        physics: const BouncingScrollPhysics(),
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
                                _datePill(
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

                if (!canMessage)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ChatUi.pagePad,
                      vertical: 6,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        disabledHint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                // ✅ Input bar modernisée + cohérente avec ConversationsScreen
                MessageInputBar(
                  controller: messageController,
                  focusNode: _inputFocus,
                  onSend: () => _sendMessage(currentUser.uid, otherUser.uid),
                  onUserActivity: _throttledTouchActiveAt,
                  enabled: canMessage,
                  isSending: _isSendingMessage,
                  disabledHint: disabledHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startOtherUserListener() {
    _otherUserSub?.cancel();
    if (widget.otherUser.uid.isEmpty) return;
    _otherUserSub = chatController.watchUserById(widget.otherUser.uid).listen(
      (user) {
        if (user == null || !mounted) return;
        setState(() => _otherUser = user);
      },
      onError: (error, stackTrace) {
        debugPrint('❌ chat otherUser listener error: $error\n$stackTrace');
      },
    );
  }

  AppUser? get _resolvedCurrentUser =>
      _userController.user ?? AuthController.instance.user;

  String? get _resolvedCurrentUid =>
      _resolvedCurrentUser?.uid ?? _authSessionService.currentUser?.uid;

  // ------------------------------
  // Delete message
  // ------------------------------
  Future<void> _confirmDeleteMessage(Message message) async {
    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Supprimer ce message',
      message: 'Voulez-vous vraiment supprimer ce message ?',
      confirmLabel: 'Supprimer',
      cancelLabel: 'Annuler',
      danger: true,
    );
    if (!confirmed) return;

    try {
      await chatController.deleteMessage(widget.conversationId, message.id);
      AdFeedback.success(
        'Message supprime',
        'Le message a ete supprime avec succes.',
      );
    } catch (e) {
      AdFeedback.error(
        'Erreur',
        'Echec de la suppression du message : $e',
      );
    }
  }

  // ------------------------------
  // Active conversation (notif throttle) - logique existante conservée
  // ------------------------------
  Future<void> _enterActiveConversation() async {
    final uid = _resolvedCurrentUid;
    if (uid == null) return;
    try {
      await chatController.setActiveConversation(
        uid: uid,
        conversationId: widget.conversationId,
      );
      _lastTouchAt = DateTime.now();
    } catch (_) {}
  }

  Future<void> _leaveActiveConversation() async {
    final uid = _resolvedCurrentUid;
    if (uid == null) return;
    try {
      await chatController.setActiveConversation(
        uid: uid,
        conversationId: null,
      );
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
    final uid = _resolvedCurrentUid;
    if (uid == null) return;
    try {
      await chatController.touchActiveConversation(uid);
    } catch (_) {}
  }

  // ------------------------------
  // Send + scroll - logique existante conservée
  // ------------------------------
  Future<void> _sendMessage(String senderId, String recipientId) async {
    final content = messageController.text.trim();
    if (content.isEmpty || _isSendingMessage) return;

    final canSend = await chatController.canSendMessage(
      senderId: senderId,
      recipientId: recipientId,
    );
    if (!canSend) {
      AdFeedback.warning(
        'Messages indisponibles',
        "L'envoi de messages est desactive pour cette conversation.",
      );
      return;
    }

    setState(() => _isSendingMessage = true);

    try {
      await chatController.sendMessage(
        conversationId: widget.conversationId,
        senderId: senderId,
        recipientId: recipientId,
        content: content,
        skipPermissionCheck: true,
      );

      messageController.clear();
      _scrollToBottom(delay: const Duration(milliseconds: 110));
      _throttledTouchActiveAt();
    } on ChatFlowException catch (error) {
      AdFeedback.error(
        'Envoi impossible',
        error.message,
      );
    } catch (_) {
      AdFeedback.error(
        'Envoi impossible',
        'Le message n\'a pas pu etre envoye. Merci de reessayer.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingMessage = false);
      }
    }
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
    if (_readSyncInFlight) return;

    final hasUnreadForCurrentUser =
        messages.any((m) => !m.estLu && m.destinataireId == currentUserId);
    if (!hasUnreadForCurrentUser) return;

    final now = DateTime.now();
    if (_lastReadSyncAt != null &&
        now.difference(_lastReadSyncAt!) < _readSyncThrottle) {
      return;
    }

    _lastReadSyncAt = now;
    _readSyncInFlight = true;
    chatController
        .markMessagesAsRead(widget.conversationId, currentUserId)
        .whenComplete(() => _readSyncInFlight = false);
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

  Widget _buildGuidedContextBanner(Conversation? conversation) {
    if (conversation == null || !conversation.hasGuidedContext) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final contextLabel = ContactContext.labelForType(conversation.contextType);
    final reasonLabel = ContactIntake.reasonLabel(
      conversation.contactReason ?? '',
    );
    final followUpStatus = ContactIntake.normalizeAgencyFollowUpStatus(
      conversation.agencyFollowUpStatus,
    );
    final followUpLabel = ContactIntake.agencyFollowUpLabel(
      conversation.agencyFollowUpStatus ?? '',
    );
    final contextTitle = conversation.contextTitle?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.secondary.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Premier contact cadre',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSecondaryContainer,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              contextTitle != null && contextTitle.isNotEmpty
                  ? '$contextLabel - $contextTitle'
                  : contextLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSecondaryContainer.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Motif: $reasonLabel. Adfoot garde ce premier echange dans le circuit officiel.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSecondaryContainer.withValues(alpha: 0.82),
                    height: 1.3,
                  ),
            ),
            if (followUpStatus != AgencyFollowUpStatus.newLead) ...[
              const SizedBox(height: 4),
              Text(
                'Suivi agence: $followUpLabel.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSecondaryContainer.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _datePill({required String label}) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _emptyChatState({required String otherUserName}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AdStatePanel(
          icon: Icons.chat_bubble_outline,
          title: 'Aucun message',
          message: 'Commence la discussion avec $otherUserName.',
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
                  ),
                ],
                border: Border.all(
                  color: cs.outline.withValues(alpha: isMe ? 0.28 : 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                    mainAxisAlignment:
                        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
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
  final bool enabled;
  final bool isSending;
  final String? disabledHint;

  const MessageInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onUserActivity,
    required this.enabled,
    required this.isSending,
    this.disabledHint,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: cs.outline.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
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
                        enabled: enabled && !isSending,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        minLines: 1,
                        maxLines: null,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        onChanged: (_) => onUserActivity(),
                        onTap: onUserActivity,
                        decoration: InputDecoration(
                          hintText:
                              enabled ? "Tapez un message…" : disabledHint,
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
                final canSend = enabled && value.text.trim().isNotEmpty;
                final canPress = canSend && !isSending;

                return AnimatedScale(
                  duration: const Duration(milliseconds: 120),
                  scale: canPress ? 1.0 : 0.98,
                  child: Ink(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: canPress
                          ? LinearGradient(
                              colors: [
                                cs.primary,
                                cs.secondaryContainer,
                              ],
                            )
                          : LinearGradient(
                              colors: [
                                cs.onSurface.withValues(alpha: 0.25),
                                cs.onSurface.withValues(alpha: 0.22),
                              ],
                            ),
                      boxShadow: [
                        if (canPress)
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                      ],
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canPress ? onSend : null,
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: isSending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
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
