import 'dart:async';
import 'dart:math' as math;

import 'package:adfoot/widgets/ad_avatar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/models/message_converstion.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/contact_intake_feedback_service.dart';
import '../controller/chat_controller.dart';
import '../models/user.dart';
import '../theme/ad_colors.dart';
import '../widgets/ad_app_bar.dart';
import '../widgets/ad_button.dart';
import '../widgets/ad_dialogs.dart';
import '../widgets/ad_feedback.dart';
import '../widgets/ad_state_panel.dart';
import 'package:adfoot/services/app_logger.dart';

part 'chat_screen_widgets.dart';

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

  static const Color onlineDot = AdColors.success;
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
  final ContactIntakeFeedbackService _feedbackService =
      ContactIntakeFeedbackService();
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
  bool _isSubmittingFeedback = false;
  final Set<String> _pendingMessageDeletes = <String>{};

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
        appBar: const AdAppBar(title: 'Chargement'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (currentUser == null) {
      return Scaffold(
        appBar: const AdAppBar(title: 'Erreur'),
        body: const Center(
          child: AdStatePanel.error(
            title: 'Session invalide',
            message: 'Utilisateur non connecté.',
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
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => _handleBackNavigation(),
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
                          'Messagerie Adfoot',
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
          decoration: BoxDecoration(color: cs.surface),
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

                      // A failed stream also arrives here with no data, and
                      // without this branch it fell through to the "aucun
                      // message" state — telling the user their conversation
                      // was empty when in fact it could not be read (offline,
                      // or a rules rejection). Losing a history is not the
                      // same thing as never having had one.
                      if (snapshot.hasError) {
                        AppLogger.debug(
                          'ChatScreen messages stream error: '
                          '${snapshot.error}',
                        );
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: AdStatePanel.error(
                            title: 'Messages indisponibles',
                            message:
                                'Impossible de charger la conversation. '
                                'Vérifiez votre réseau puis réessayez.',
                          ),
                        );
                      }

                      final messages = snapshot.data ?? const <Message>[];

                      if (messages.isEmpty) {
                        return _emptyChatState(
                          otherUserName: otherUser.nom,
                          canMessage: canMessage,
                        );
                      }

                      // ✅ Marque comme lu (logique existante conservée)
                      _markMessagesAsRead(messages, currentUser.uid);

                      // ✅ Scroll au bas après frame (comme avant)
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToBottom();
                      });

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

                          final showDateHeader = _shouldShowDateHeader(
                            messages,
                            index,
                          );

                          return Column(
                            children: [
                              if (showDateHeader)
                                _datePill(
                                  label: _formatDayLabel(message.dateEnvoi),
                                ),
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
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.8,
                        ),
                        borderRadius: BorderRadius.circular(8),
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
    _otherUserSub = chatController
        .watchUserById(widget.otherUser.uid)
        .listen(
          (user) {
            if (user == null || !mounted) return;
            setState(() => _otherUser = user);
          },
          onError: (error, stackTrace) {
            AppLogger.debug(
              '❌ chat otherUser listener error: $error\n$stackTrace',
            );
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
    if (_pendingMessageDeletes.contains(message.id)) {
      return;
    }

    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Supprimer ce message',
      message: 'Voulez-vous vraiment supprimer ce message ?',
      confirmLabel: 'Supprimer',
      cancelLabel: 'Annuler',
      danger: true,
    );
    if (!confirmed) return;

    setState(() => _pendingMessageDeletes.add(message.id));
    try {
      await chatController.deleteMessage(widget.conversationId, message.id);
      AdFeedback.success(
        'Message supprimé',
        'Le message a été supprimé avec succès.',
      );
    } on ChatFlowException catch (error) {
      AdFeedback.error('Suppression impossible', error.message);
    } catch (_) {
      AdFeedback.error(
        'Suppression impossible',
        'Le message n’a pas pu être supprimé. Merci de réessayer.',
      );
    } finally {
      if (mounted) {
        setState(() => _pendingMessageDeletes.remove(message.id));
      }
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

    setState(() => _isSendingMessage = true);

    try {
      final canSend = await chatController.canSendMessage(
        senderId: senderId,
        recipientId: recipientId,
      );
      if (!canSend) {
        AdFeedback.warning(
          'Messages indisponibles',
          "L’envoi de messages est désactivé pour cette conversation.",
        );
        return;
      }

      await chatController.sendMessage(
        conversationId: widget.conversationId,
        senderId: senderId,
        recipientId: recipientId,
        content: content,
        skipPermissionCheck: true,
      );

      // The user can navigate away (e.g. the back button, see
      // _handleBackNavigation) while sendMessage is still in flight. The
      // message is already delivered at this point, so bail out quietly
      // instead of touching a possibly-disposed messageController/scroll
      // controller -- doing so used to fall into the generic catch below
      // and show a misleading "Envoi impossible" toast for a message that
      // actually sent.
      if (!mounted) {
        return;
      }

      messageController.clear();
      _scrollToBottom(delay: const Duration(milliseconds: 110));
      _throttledTouchActiveAt();
    } on ChatFlowException catch (error) {
      AdFeedback.error('Envoi impossible', error.message);
    } catch (_) {
      AdFeedback.error(
        'Envoi impossible',
        'Le message n’a pas pu être envoyé. Merci de réessayer.',
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

    final hasUnreadForCurrentUser = messages.any(
      (m) => !m.estLu && m.destinataireId == currentUserId,
    );
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

  bool _shouldShowDateHeader(List<Message> messages, int index) {
    if (index < 0 || index >= messages.length) {
      return false;
    }

    final currentDay = _dayKey(messages[index].dateEnvoi);
    final nextOlderIndex = index + 1;
    if (nextOlderIndex >= messages.length) {
      return true;
    }

    return _dayKey(messages[nextOlderIndex].dateEnvoi) != currentDay;
  }

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
    final feedbackLabel = conversation.hasParticipantFeedback
        ? ContactIntakeFeedbackStatus.label(
            conversation.latestParticipantFeedbackStatus,
          )
        : null;
    final feedbackNote = conversation.latestParticipantFeedbackNote?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.secondary.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Premier contact cadré',
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
              'Motif : $reasonLabel. Adfoot garde ce premier échange dans le circuit officiel.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSecondaryContainer.withValues(alpha: 0.82),
                height: 1.3,
              ),
            ),
            if (followUpStatus != AgencyFollowUpStatus.newLead) ...[
              const SizedBox(height: 4),
              Text(
                'Suivi agence : $followUpLabel.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSecondaryContainer.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (feedbackLabel != null) ...[
              const SizedBox(height: 8),
              _FeedbackSignalPill(
                label: 'Retour utilisateur : $feedbackLabel',
                note: feedbackNote,
              ),
            ],
            if (_resolveContactIntakeId(conversation) != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: AdButton(
                  onPressed: _isSubmittingFeedback
                      ? null
                      : () => _showContactFeedbackSheet(conversation),
                  kind: AdButtonKind.outline,
                  size: AdButtonSize.compact,
                  expanded: false,
                  leading: Icons.assignment_turned_in_outlined,
                  label: 'Donner un retour sur la mise en relation',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _resolveContactIntakeId(Conversation conversation) {
    final linkedIntakeId = conversation.contactIntakeId?.trim();
    if (linkedIntakeId != null && linkedIntakeId.isNotEmpty) {
      return linkedIntakeId;
    }

    final conversationId = conversation.id.trim().isNotEmpty
        ? conversation.id.trim()
        : widget.conversationId.trim();
    return conversationId.isEmpty ? null : conversationId;
  }

  Future<void> _showContactFeedbackSheet(Conversation conversation) async {
    final contactIntakeId = _resolveContactIntakeId(conversation);
    if (contactIntakeId == null || contactIntakeId.isEmpty) {
      return;
    }

    final draft = await showModalBottomSheet<_ContactFeedbackDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactFeedbackSheet(
        initialStatus: conversation.latestParticipantFeedbackStatus,
        initialNote: conversation.latestParticipantFeedbackNote,
      ),
    );
    if (draft == null) {
      return;
    }

    setState(() => _isSubmittingFeedback = true);
    try {
      final result = await _feedbackService.submitFeedback(
        contactIntakeId: contactIntakeId,
        conversationId: widget.conversationId,
        status: draft.status,
        note: draft.note,
      );

      if (result.success) {
        AdFeedback.success(
          'Retour enregistré',
          'Merci. Ce signal aide Adfoot à mieux suivre cette opportunité.',
        );
      } else {
        AdFeedback.error('Retour impossible', result.message);
      }
    } catch (_) {
      AdFeedback.error(
        'Retour impossible',
        'Le retour n’a pas pu être transmis. Merci de réessayer.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingFeedback = false);
      }
    }
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

  Widget _emptyChatState({
    required String otherUserName,
    required bool canMessage,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AdStatePanel(
          icon: Icons.chat_bubble_outline,
          title: 'Aucun message',
          message: canMessage
              ? 'Envoyez un premier message à $otherUserName.'
              : 'La conversation est ouverte, mais la messagerie est désactivée pour le moment.',
        ),
      ),
    );
  }
}
