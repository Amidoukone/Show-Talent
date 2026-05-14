import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:adfoot/widgets/contact_intake_sheet.dart';

import 'chat_screen.dart';

class SelectUserScreen extends StatefulWidget {
  const SelectUserScreen({super.key});

  @override
  State<SelectUserScreen> createState() => _SelectUserScreenState();
}

class _SelectUserScreenState extends State<SelectUserScreen> {
  final UserController userController = Get.find<UserController>();
  final ChatController chatController = Get.find<ChatController>();
  final AuthController authController = Get.find<AuthController>();
  final AuthSessionService _authSessionService = AuthSessionService();

  final TextEditingController searchController = TextEditingController();
  final RxString searchTerm = ''.obs;
  String? _busyConversationUserId;

  AppUser? _resolvedCurrentUser() {
    return userController.user ?? authController.user;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvelle conversation'),
        centerTitle: true,
      ),
      body: Obx(() {
        final currentUser = _resolvedCurrentUser();
        final currentUid =
            currentUser?.uid ?? _authSessionService.currentUser?.uid;

        if (currentUid == null) {
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

        final users = userController.userList.where((user) {
          return user.uid != currentUid && user.canAppearInMessagingDirectory;
        }).toList();

        final filteredUsers = users.where((user) {
          return user.nom.toLowerCase().contains(searchTerm.value);
        }).toList();

        return Column(
          children: [
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
                    hintText: 'Rechercher un utilisateur...',
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
            Expanded(
              child: Builder(
                builder: (context) {
                  if (users.isEmpty) {
                    return const AdStatePanel.empty(
                      title: 'Aucun utilisateur disponible',
                      message:
                          'Il n’y a actuellement aucun utilisateur avec qui discuter.',
                    );
                  }

                  if (filteredUsers.isEmpty) {
                    return const AdStatePanel.empty(
                      title: 'Aucun résultat',
                      message:
                          'Aucun utilisateur ne correspond à votre recherche.',
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
                            final resolvedCurrentUser = _resolvedCurrentUser();
                            if (resolvedCurrentUser == null) {
                              AdFeedback.error(
                                'Erreur',
                                'Utilisateur non connecté.',
                              );
                              return;
                            }

                            if (!resolvedCurrentUser.allowMessages ||
                                !user.allowMessages) {
                              AdFeedback.warning(
                                'Messages indisponibles',
                                !resolvedCurrentUser.allowMessages
                                    ? 'Vous avez désactivé les messages.'
                                    : 'Cet utilisateur a désactivé les messages.',
                              );
                              return;
                            }

                            final existingConversationId =
                                await chatController.findExistingConversationId(
                              currentUserId: resolvedCurrentUser.uid,
                              otherUserId: user.uid,
                            );

                            if (existingConversationId != null &&
                                existingConversationId.isNotEmpty) {
                              if (!mounted) {
                                return;
                              }
                              await Get.to(
                                () => ChatScreen(
                                  conversationId: existingConversationId,
                                  otherUser: user,
                                ),
                              );
                              return;
                            }

                            final draft =
                                await Get.bottomSheet<GuidedContactDraft>(
                              ContactIntakeSheet(
                                currentUser: resolvedCurrentUser,
                                otherUser: user,
                                context: ContactContext.discovery(
                                  title: 'Sélection utilisateur',
                                ),
                              ),
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                            );

                            if (draft == null) {
                              return;
                            }

                            final result =
                                await chatController.startGuidedConversation(
                              currentUser: resolvedCurrentUser,
                              otherUser: user,
                              context: draft.context,
                              contactReason: draft.reasonCode,
                              introMessage: draft.introMessage,
                            );

                            if (result.createdIntake) {
                              AdFeedback.info(
                                'Contact enregistré',
                                'Le premier contact a été cadré et transmis via Adfoot.',
                              );
                            }

                            final conversationId = result.conversationId.trim();
                            if (conversationId.isEmpty) {
                              AdFeedback.error(
                                'Erreur',
                                'Conversation indisponible pour le moment.',
                              );
                              return;
                            }

                            if (!mounted) {
                              return;
                            }
                            await Get.to(
                              () => ChatScreen(
                                conversationId: conversationId,
                                otherUser: user,
                              ),
                            );
                          } on ChatFlowException catch (error) {
                            AdFeedback.error(
                              'Erreur',
                              error.message,
                            );
                          } catch (_) {
                            AdFeedback.error(
                              'Erreur',
                              'Impossible de démarrer la conversation.',
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
                },
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onTap,
    this.isLoading = false,
  });

  final AppUser user;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final initial =
        user.nom.trim().isNotEmpty ? user.nom.trim()[0].toUpperCase() : '?';

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
