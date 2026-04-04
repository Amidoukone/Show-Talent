import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'chat_screen.dart';

class SelectUserScreen extends StatefulWidget {
  const SelectUserScreen({super.key});

  @override
  State<SelectUserScreen> createState() => _SelectUserScreenState();
}

class _SelectUserScreenState extends State<SelectUserScreen> {
  // ✅ Réutilise les controllers existants
  final UserController userController = Get.find<UserController>();

  final ChatController chatController = Get.find<ChatController>();

  final AuthController authController = Get.find<AuthController>();

  final TextEditingController searchController = TextEditingController();
  final RxString searchTerm = ''.obs;
  String? _busyConversationUserId;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currentUid = authController.user?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvelle conversation'),
        centerTitle: true,
      ),
      body: currentUid == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: AdStatePanel.error(
                  title: 'Session invalide',
                  message: 'Utilisateur non connecte.',
                ),
              ),
            )
          : Column(
              children: [
                // 🔍 Barre de recherche moderne
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.6),
                      ),
                    ),
                    child: TextField(
                      controller: searchController,
                      onChanged: (value) =>
                          searchTerm.value = value.toLowerCase(),
                      decoration: InputDecoration(
                        hintText: 'Rechercher un utilisateur…',
                        prefixIcon: Icon(
                          Icons.search,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // 👥 Liste utilisateurs
                Expanded(
                  child: Obx(() {
                    final users = userController.userList.where((user) {
                      return user.uid != currentUid &&
                          user.nom.isNotEmpty &&
                          user.emailVerified == true &&
                          user.estActif == true;
                    }).toList();

                    if (users.isEmpty) {
                      return const AdStatePanel.empty(
                        title: "Aucun utilisateur disponible",
                        message:
                            "Il n'y a actuellement aucun utilisateur avec qui discuter.",
                      );
                    }

                    final filteredUsers = users.where((user) {
                      return user.nom.toLowerCase().contains(searchTerm.value);
                    }).toList();

                    if (filteredUsers.isEmpty) {
                      return const AdStatePanel.empty(
                        title: "Aucun résultat",
                        message:
                            "Aucun utilisateur ne correspond à votre recherche.",
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      itemCount: filteredUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final AppUser user = filteredUsers[index];

                        return _UserCard(
                          user: user,
                          isLoading: _busyConversationUserId == user.uid,
                          onTap: () async {
                            if (_busyConversationUserId != null) {
                              return;
                            }

                            setState(() => _busyConversationUserId = user.uid);
                            try {
                              final conversationId =
                                  await chatController.createOrGetConversation(
                                currentUserId: currentUid,
                                otherUserId: user.uid,
                              );

                              if (conversationId.trim().isEmpty) {
                                AdFeedback.error(
                                  'Erreur',
                                  'Conversation indisponible pour le moment.',
                                );
                                return;
                              }

                              if (!mounted) return;
                              await Get.to(() => ChatScreen(
                                    conversationId: conversationId,
                                    otherUser: user,
                                  ));
                            } catch (e) {
                              AdFeedback.error(
                                'Erreur',
                                'Impossible de demarrer la conversation.',
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _busyConversationUserId = null);
                              }
                            }
                          },
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
    );
  }
}

/// ------------------------------
/// UI Components
/// ------------------------------

class _UserCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback? onTap;
  final bool isLoading;

  const _UserCard({
    required this.user,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final initial =
        user.nom.trim().isNotEmpty ? user.nom.trim()[0].toUpperCase() : "?";

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.surfaceContainerHighest,
                backgroundImage: user.photoProfil.isNotEmpty
                    ? NetworkImage(user.photoProfil)
                    : null,
                child: user.photoProfil.isEmpty
                    ? Text(
                        initial,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.role.isNotEmpty ? user.role : 'Rôle non renseigné',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isLoading ? Icons.hourglass_top : Icons.chevron_right,
                color: isLoading
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
