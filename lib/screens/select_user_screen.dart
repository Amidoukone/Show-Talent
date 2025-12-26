import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/models/user.dart';
import 'chat_screen.dart';

class SelectUserScreen extends StatefulWidget {
  const SelectUserScreen({super.key});

  @override
  State<SelectUserScreen> createState() => _SelectUserScreenState();
}

class _SelectUserScreenState extends State<SelectUserScreen> {
  // ✅ Réutilise les controllers existants
  final UserController userController = Get.isRegistered<UserController>()
      ? Get.find<UserController>()
      : Get.put(UserController(), permanent: true);

  final ChatController chatController = Get.isRegistered<ChatController>()
      ? Get.find<ChatController>()
      : Get.put(ChatController(), permanent: true);

  final AuthController authController = Get.find<AuthController>();

  final TextEditingController searchController = TextEditingController();
  final RxString searchTerm = ''.obs;

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
          ? const Center(child: Text("Utilisateur non connecté."))
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
                      onChanged: (value) => searchTerm.value = value.toLowerCase(),
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
                      return _EmptyState(
                        icon: Icons.group_off_outlined,
                        title: "Aucun utilisateur disponible",
                        subtitle:
                            "Il n’y a actuellement aucun utilisateur avec qui discuter.",
                      );
                    }

                    final filteredUsers = users.where((user) {
                      return user.nom.toLowerCase().contains(searchTerm.value);
                    }).toList();

                    if (filteredUsers.isEmpty) {
                      return _EmptyState(
                        icon: Icons.search_off,
                        title: "Aucun résultat",
                        subtitle: "Aucun utilisateur ne correspond à ta recherche.",
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
                          onTap: () async {
                            try {
                              final conversationId =
                                  await chatController.createOrGetConversation(
                                currentUserId: currentUid,
                                otherUserId: user.uid,
                              );

                              Get.to(() => ChatScreen(
                                    conversationId: conversationId,
                                    otherUser: user,
                                  ));
                            } catch (e) {
                              Get.snackbar(
                                'Erreur',
                                'Impossible de démarrer la conversation : $e',
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                                snackPosition: SnackPosition.BOTTOM,
                              );
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
  final VoidCallback onTap;

  const _UserCard({
    required this.user,
    required this.onTap,
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
                backgroundImage:
                    user.photoProfil.isNotEmpty ? NetworkImage(user.photoProfil) : null,
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
                Icons.chevron_right,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
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
