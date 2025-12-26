import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controller/auth_controller.dart';
import '../controller/chat_controller.dart';
import '../controller/user_controller.dart';
import '../models/user.dart';
import 'chat_screen.dart';
import 'select_user_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  // ✅ Réutilise le ChatController existant, sinon l’instancie (comme ta structure)
  final ChatController chatController = Get.isRegistered<ChatController>()
      ? Get.find<ChatController>()
      : Get.put(ChatController(), permanent: true);

  // ✅ Réutilise AuthController existant
  final AuthController authController = Get.find<AuthController>();

  // ✅ On s’appuie sur UserController.userList pour éviter FutureBuilder par item
  final UserController userController = Get.isRegistered<UserController>()
      ? Get.find<UserController>()
      : Get.put(UserController(), permanent: true);

  @override
  void initState() {
    super.initState();
    // ✅ Synchronisation douce au montage (anti timing issues)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      chatController.refreshConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Conversations"),
        centerTitle: true,
        actions: [
          // ✅ Refresh manuel (optionnel, non destructif)
          IconButton(
            tooltip: "Rafraîchir",
            onPressed: () => chatController.refreshConversations(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Obx(() {
        final currentUserId = authController.user?.uid;
        if (currentUserId == null) {
          return const Center(child: Text("Utilisateur non connecté."));
        }

        final conversations = chatController.conversations;

        if (conversations.isEmpty) {
          return _EmptyState(
            onNewChat: () => Get.to(() => const SelectUserScreen()),
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

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final conversation = sorted[index];

            final otherUserId = conversation.utilisateurIds.firstWhere(
              (id) => id != currentUserId,
              orElse: () => '',
            );

            if (otherUserId.isEmpty) {
              return _InfoCard(
                title: "Utilisateur inconnu",
                subtitle: "Impossible d'identifier l'autre participant.",
                icon: Icons.help_outline,
              );
            }

            final otherUser = usersById[otherUserId];

            // ✅ Placeholder stable si la liste users n’est pas encore prête
            if (otherUser == null) {
              return const _SkeletonConversationTile();
            }

            // ✅ On conserve la logique de filtrage
            if (otherUser.estActif != true || otherUser.emailVerified != true) {
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
                if (unreadCount > 0) {
                  await chatController.markMessagesAsRead(
                    conversation.id,
                    currentUserId,
                  );
                }

                Get.to(() => ChatScreen(
                      conversationId: conversation.id,
                      otherUser: otherUser,
                    ));
              },
              onLongPress: () => _confirmDelete(conversation.id),
              // ✅ Swipe to delete (moderne) sans supprimer le long-press
              onSwipeDelete: () => _confirmDelete(conversation.id),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.to(() => const SelectUserScreen()),
        backgroundColor: const Color.fromARGB(255, 20, 147, 4),
        icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
        label: const Text(
          "Nouveau",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        elevation: 2,
      ),
    );
  }

  void _confirmDelete(String conversationId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer la conversation"),
        content: const Text("Voulez-vous vraiment supprimer cette conversation ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await chatController.deleteConversation(conversationId);
              Get.snackbar(
                'Conversation supprimée',
                '',
                snackPosition: SnackPosition.BOTTOM,
              );
            },
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatDateOrTime(DateTime? dateTime) {
    if (dateTime == null) return "Inconnue";

    final now = DateTime.now();
    final isToday =
        now.day == dateTime.day && now.month == dateTime.month && now.year == dateTime.year;

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
      fontWeight: isUnread ? FontWeight.w800 : FontWeight.w700,
      letterSpacing: 0.1,
    );

    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: isUnread ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.7),
      fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
    );

    final dateStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      fontWeight: FontWeight.w600,
    );

    final avatarBg = theme.colorScheme.surfaceContainerHighest;

    final card = Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
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
    );

    // ✅ Swipe-to-delete moderne (sans supprimer long-press)
    return Dismissible(
      key: ValueKey("conv_${user.uid}_${dateLabel}_${unreadCount}_${lastMessage.hashCode}"),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onSwipeDelete();
        return false; // on garde confirmation via dialog
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.85),
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
    final initial = (name.trim().isNotEmpty) ? name.trim().substring(0, 1).toUpperCase() : "?";

    return CircleAvatar(
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
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final shown = count > 99 ? "99+" : "$count";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal,
        borderRadius: BorderRadius.circular(20),
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
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 56,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              "Aucune conversation",
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Démarre une discussion avec un utilisateur pour voir tes conversations ici.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onNewChat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text("Nouveau message"),
            ),
          ],
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
              radius: 22,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(icon, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
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
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
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
