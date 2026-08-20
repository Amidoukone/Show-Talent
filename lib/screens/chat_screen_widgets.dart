part of 'chat_screen.dart';

class _FeedbackSignalPill extends StatelessWidget {
  const _FeedbackSignalPill({
    required this.label,
    this.note,
  });

  final String label;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w900,
                ),
          ),
          if (note?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              note!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSecondaryContainer.withValues(alpha: 0.78),
                    height: 1.25,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactFeedbackDraft {
  const _ContactFeedbackDraft({
    required this.status,
    required this.note,
  });

  final String status;
  final String note;
}

class _ContactFeedbackSheet extends StatefulWidget {
  const _ContactFeedbackSheet({
    this.initialStatus,
    this.initialNote,
  });

  final String? initialStatus;
  final String? initialNote;

  @override
  State<_ContactFeedbackSheet> createState() => _ContactFeedbackSheetState();
}

class _ContactFeedbackSheetState extends State<_ContactFeedbackSheet> {
  final TextEditingController _noteController = TextEditingController();
  late String _selectedStatus;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _selectedStatus = ContactIntakeFeedbackStatus.normalize(
      widget.initialStatus,
    );
    _noteController.text = widget.initialNote?.trim() ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _requiresNote {
    return _selectedStatus == ContactIntakeFeedbackStatus.issueReported ||
        _selectedStatus == ContactIntakeFeedbackStatus.trialScheduled ||
        _selectedStatus == ContactIntakeFeedbackStatus.opportunitySerious;
  }

  List<_FeedbackOption> get _options => const <_FeedbackOption>[
        _FeedbackOption(
          status: ContactIntakeFeedbackStatus.noResponse,
          title: 'Pas encore de réponse',
          description: 'La conversation existe mais rien de concret encore.',
          icon: Icons.hourglass_empty_rounded,
        ),
        _FeedbackOption(
          status: ContactIntakeFeedbackStatus.discussionStarted,
          title: 'Discussion engagée',
          description: 'Un échange utile a commencé entre les deux parties.',
          icon: Icons.forum_outlined,
        ),
        _FeedbackOption(
          status: ContactIntakeFeedbackStatus.trialScheduled,
          title: 'Essai / rendez-vous prévu',
          description: 'Une date, un essai ou un appel concret est prévu.',
          icon: Icons.event_available_outlined,
        ),
        _FeedbackOption(
          status: ContactIntakeFeedbackStatus.opportunitySerious,
          title: 'Opportunité sérieuse',
          description: 'La piste semble crédible pour la suite du talent.',
          icon: Icons.workspace_premium_outlined,
        ),
        _FeedbackOption(
          status: ContactIntakeFeedbackStatus.notRelevant,
          title: 'Non pertinent',
          description: 'La mise en relation ne correspond finalement pas.',
          icon: Icons.block_outlined,
        ),
        _FeedbackOption(
          status: ContactIntakeFeedbackStatus.issueReported,
          title: 'Problème signalé',
          description: 'Comportement suspect, abus, promesse floue ou risque.',
          icon: Icons.report_problem_outlined,
        ),
      ];

  void _submit() {
    final note = _noteController.text.trim();
    if (_requiresNote && note.length < 8) {
      setState(() {
        _errorText = 'Ajoutez une note courte pour contextualiser ce retour.';
      });
      return;
    }

    Get.back<_ContactFeedbackDraft>(
      result: _ContactFeedbackDraft(
        status: _selectedStatus,
        note: note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;
    final bottomInset = media.viewInsets.bottom;
    final availableHeight = math.max(
      260.0,
      media.size.height - bottomInset - media.padding.top - 8,
    );
    final sheetMaxHeight = math.min(media.size.height * 0.92, availableHeight);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: sheetMaxHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                top: BorderSide(color: cs.outline.withValues(alpha: 0.22)),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    // Guardrail: keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: cs.outline.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Retour sur la mise en relation',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: cs.onSurface,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ces informations restent structurées pour Adfoot. Elles aident à accompagner les talents sans ouvrir la discussion privée.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.72),
                                    height: 1.35,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        ..._options.map((option) {
                          final selected = _selectedStatus == option.status;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _FeedbackOptionTile(
                              option: option,
                              selected: selected,
                              onTap: () {
                                setState(() {
                                  _selectedStatus = option.status;
                                  _errorText = null;
                                });
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _noteController,
                          maxLines: 3,
                          maxLength: 500,
                          textInputAction: TextInputAction.newline,
                          scrollPadding: const EdgeInsets.only(bottom: 120),
                          decoration: InputDecoration(
                            labelText: 'Précision utile pour Adfoot',
                            hintText:
                                'Ex. : essai prévu samedi, recruteur sérieux, pas de réponse, comportement suspect...',
                            errorText: _errorText,
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(
                      top: BorderSide(
                        color: cs.outline.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Get.back<_ContactFeedbackDraft?>(),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _submit,
                            icon: const Icon(Icons.send_rounded),
                            label: const Text('Envoyer le retour'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackOption {
  const _FeedbackOption({
    required this.status,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String status;
  final String title;
  final String description;
  final IconData icon;
}

class _FeedbackOptionTile extends StatelessWidget {
  const _FeedbackOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _FeedbackOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.6)
          : cs.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: 0.45)
                  : cs.outline.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              Icon(
                option.icon,
                color:
                    selected ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.68),
                            height: 1.25,
                          ),
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: cs.primary),
            ],
          ),
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
        AdAvatar(
          radius: ChatUi.avatarRadius,
          backgroundColor: fallbackBg,
          photoUrl: user.photoProfil,
          fallback: Text(
            initial,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
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
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.only(
          left: 10,
          right: 10,
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
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: cs.outline.withValues(alpha: 0.35),
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
                      color: canPress
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.24),
                      boxShadow: [
                        if (canPress)
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
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
