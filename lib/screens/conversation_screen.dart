import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controller/auth_controller.dart';
import '../controller/chat_controller.dart';
import '../controller/user_controller.dart';
import '../models/user.dart';
import '../services/auth/auth_session_service.dart';
import '../widgets/ad_dialogs.dart';
import '../widgets/ad_feedback.dart';
import '../widgets/ad_state_panel.dart';
import 'chat_screen.dart';
import 'select_user_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  // ✅ Réutilise le ChatController existant, sinon l’instancie (comme ta structure)
  final ChatController chatController = Get.find<ChatController>();

  // ✅ Réutilise AuthController existant
  final AuthController authController = Get.find<AuthController>();

  // ✅ On s’appuie sur UserController.userList pour éviter FutureBuilder par item
  final UserController userController = Get.find<UserController>();
  final AuthSessionService _authSessionService = AuthSessionService();
  bool _isOpeningConversation = false;
  final Set<String> _deletingConversationIds = <String>{};

  @override
  void initState() {
    super.initState();
    // ✅ Synchronisation douce au montage (anti timing issues)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      chatController.refreshConversations();
    });
  }

  Future<void> _handleRefresh() async {
    chatController.refreshConversations();
    await Future<void>.delayed(const Duration(milliseconds: 180));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.6)),
              ),
              child: const Icon(Icons.messenger_outline, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Conversations',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Messages et mises en relation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // ✅ Refresh manuel (optionnel, non destructif)
          IconButton(
            tooltip: "Rafraîchir",
            onPressed: () => chatController.refreshConversations(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.to(() => const SelectUserScreen()),
        backgroundColor: cs.primary,
        icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
        label: const Text(
          'Nouveau',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        elevation: 3,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.surface,
              cs.surfaceContainerHigh,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Obx(() {
            final currentUser = userController.user ?? authController.user;
            final currentUserId =
                currentUser?.uid ?? _authSessionService.currentUser?.uid;
            if (currentUserId == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: AdStatePanel.error(
                    title: 'Session invalide',
                    message: 'Utilisateur non connecté.',
                  ),
                ),
              );
            }

            if (currentUser == null) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final conversations = chatController.conversations;

            if (conversations.isEmpty) {
              return RefreshIndicator.adaptive(
                onRefresh: _handleRefresh,
                color: cs.primary,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 80),
                  children: [
                    _EmptyState(
                      onNewChat: () => Get.to(() => const SelectUserScreen()),
                    ),
                  ],
                ),
              );
            }

            // ✅ Tri local
            final sorted = List.of(conversations)
              ..sort((a, b) => (b.lastMessageDate ?? DateTime(0))
                  .compareTo(a.lastMessageDate ?? DateTime(0)));

            // ✅ Map uid -> AppUser pour accès O(1)
            final Map<String, AppUser> usersById = {
              for (final u in userController.userList) u.uid: u,
            };

            return RefreshIndicator.adaptive(
              onRefresh: _handleRefresh,
              color: cs.primary,
              edgeOffset: 6,
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 86),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final conversation = sorted[index];

                  final otherUserId = conversation.utilisateurIds.firstWhere(
                    (id) => id != currentUserId,
                    orElse: () => '',
                  );

                  if (otherUserId.isEmpty) {
                    return _InfoCard(
                      title: "Utilisateur inconnu",
                      subtitle: "Impossible d’identifier l’autre participant.",
                      icon: Icons.help_outline,
                    );
                  }

                  final otherUser = usersById[otherUserId];

                  // ✅ Placeholder stable si la liste users n’est pas encore prête
                  if (otherUser == null) {
                    return const _SkeletonConversationTile();
                  }

                  // ✅ On conserve la logique de filtrage
                  if (!otherUser.canAppearInMessagingDirectory) {
                    return _InfoCard(
                      title: "Utilisateur inactif ou non vérifié",
                      subtitle: "Cette conversation n’est pas disponible.",
                      icon: Icons.lock_outline,
                    );
                  }

                  final unreadCount = conversation.unreadMessagesCount;
                  final isUnread = unreadCount > 0;

                  return _ConversationCard(
                    colorScheme: cs,
                    user: otherUser,
                    lastMessage: (conversation.lastMessage != null &&
                            conversation.lastMessage!.trim().isNotEmpty)
                        ? conversation.lastMessage!
                        : "Aucun message",
                    dateLabel: _formatDateOrTime(conversation.lastMessageDate),
                    isUnread: isUnread,
                    unreadCount: unreadCount,
                    onTap: () async {
                      if (_isOpeningConversation) {
                        return;
                      }

                      setState(() => _isOpeningConversation = true);
                      try {
                        if (unreadCount > 0) {
                          await chatController.markMessagesAsRead(
                            conversation.id,
                            currentUserId,
                          );
                        }

                        await Get.to(() => ChatScreen(
                              conversationId: conversation.id,
                              otherUser: otherUser,
                            ));
                      } finally {
                        if (mounted) {
                          setState(() => _isOpeningConversation = false);
                        }
                      }
                    },
                    onLongPress: () => _confirmDelete(conversation.id),
                    // ✅ Swipe to delete (moderne) sans supprimer le long-press
                    onSwipeDelete: () => _confirmDelete(conversation.id),
                  );
                },
              ),
            );
          }),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String conversationId) async {
    if (_deletingConversationIds.contains(conversationId)) {
      return;
    }

    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Supprimer la conversation',
      message: 'Voulez-vous vraiment supprimer cette conversation ?',
      confirmLabel: 'Supprimer',
      cancelLabel: 'Annuler',
      danger: true,
    );
    if (!confirmed) return;

    setState(() => _deletingConversationIds.add(conversationId));
    try {
      await chatController.deleteConversation(conversationId);
      AdFeedback.success(
        'Conversation supprimée',
        'La conversation a été supprimée avec succès.',
      );
    } catch (e) {
      AdFeedback.error(
        'Erreur',
        'Impossible de supprimer la conversation : $e',
      );
    } finally {
      if (mounted) {
        setState(() => _deletingConversationIds.remove(conversationId));
      }
    }
  }

  String _formatDateOrTime(DateTime? dateTime) {
    if (dateTime == null) return "Inconnue";

    final now = DateTime.now();
    final isToday = now.day == dateTime.day &&
        now.month == dateTime.month &&
        now.year == dateTime.year;

    return isToday
        ? DateFormat('HH:mm').format(dateTime)
        : DateFormat('dd/MM/yyyy').format(dateTime);
  }
}

/// ------------------------------
/// Widgets UI (modernes & safe)
/// ------------------------------

class _ConversationCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final AppUser user;
  final String lastMessage;
  final String dateLabel;
  final bool isUnread;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeDelete;

  const _ConversationCard({
    required this.colorScheme,
    required this.user,
    required this.lastMessage,
    required this.dateLabel,
    required this.isUnread,
    required this.unreadCount,
    required this.onTap,
    required this.onLongPress,
    required this.onSwipeDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: isUnread ? FontWeight.w900 : FontWeight.w700,
      letterSpacing: 0.15,
    );

    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color:
          theme.colorScheme.onSurface.withValues(alpha: isUnread ? 0.92 : 0.68),
      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: 0.05,
    );

    final dateStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      fontWeight: FontWeight.w700,
    );

    final avatarBg =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnread
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.dividerColor.withValues(alpha: 0.8),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _Avatar(
                  name: user.nom,
                  photoUrl: user.photoProfil,
                  background: avatarBg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ligne 1 : Nom + Date
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.nom.isNotEmpty ? user.nom : "Utilisateur",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(dateLabel, style: dateStyle),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Ligne 2 : Dernier message + badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtitleStyle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (unreadCount > 0) _UnreadBadge(count: unreadCount),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // ✅ Swipe-to-delete moderne (sans supprimer long-press)
    return Dismissible(
      key: ValueKey("conv_${user.uid}"),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onSwipeDelete();
        return false; // on garde confirmation via dialog
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: card,
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String photoUrl;
  final Color background;

  const _Avatar({
    required this.name,
    required this.photoUrl,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final initial = (name.trim().isNotEmpty)
        ? name.trim().substring(0, 1).toUpperCase()
        : "?";

    return Stack(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: background,
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty
              ? Text(
                  initial,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                )
              : null,
        ),
        Positioned(
          bottom: 2,
          right: 2,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
              border: Border.all(
                  color: Colors.black.withValues(alpha: 0.65), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = count > 99 ? "99+" : "$count";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Text(
        shown,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNewChat;

  const _EmptyState({required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AdStatePanel.empty(
          title: 'Aucune conversation',
          message:
              'Démarrez une discussion avec un utilisateur pour retrouver vos échanges ici.',
          action: FilledButton.icon(
            onPressed: onNewChat,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Nouvelle discussion'),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(icon,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonConversationTile extends StatelessWidget {
  const _SkeletonConversationTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(10),
          ),
        );

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(140, 14),
                  const SizedBox(height: 8),
                  bar(double.infinity, 12),
                ],
              ),
            ),
            const SizedBox(width: 10),
            bar(36, 18),
          ],
        ),
      ),
    );
  }
}
