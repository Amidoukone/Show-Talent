import 'package:adfoot/widgets/ad_avatar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/widgets/ad_agency_badge.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_surface_card.dart';
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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AdAppBar(
        title: l10n.selectUserTitle,
        subtitle: l10n.selectUserSubtitle,
        showBottomDivider: true,
      ),
      body: Obx(() {
        final currentUser = _resolvedCurrentUser();
        final currentUid =
            currentUser?.uid ?? _authSessionService.currentUser?.uid;

        if (currentUid == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AdStatePanel.error(
                title: l10n.profileInvalidSessionTitle,
                message: l10n.profileNotSignedInMessage,
              ),
            ),
          );
        }

        if (currentUser == null) {
          return const Center(child: CircularProgressIndicator());
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
                  borderRadius: BorderRadius.circular(AdRadius.md),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.6),
                  ),
                ),
                child: TextField(
                  controller: searchController,
                  onChanged: (value) =>
                      searchTerm.value = value.trim().toLowerCase(),
                  decoration: InputDecoration(
                    hintText: l10n.selectUserSearchHint,
                    prefixIcon: Icon(
                      Icons.search,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                    suffixIcon: searchTerm.value.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.commonClear,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              searchController.clear();
                              searchTerm.value = '';
                            },
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
                    return AdStatePanel.empty(
                      title: l10n.selectUserEmptyTitle,
                      message: l10n.selectUserEmptyMessage,
                    );
                  }

                  if (filteredUsers.isEmpty) {
                    return AdStatePanel.empty(
                      title: l10n.selectUserNoResultsTitle,
                      message: l10n.selectUserNoResultsMessage,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: filteredUsers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
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
                                l10n.profileMessagingErrorTitle,
                                l10n.profileNotSignedInMessage,
                              );
                              return;
                            }

                            if (!resolvedCurrentUser.allowMessages ||
                                !user.allowMessages) {
                              AdFeedback.warning(
                                l10n.profileMessagingDisabledTitle,
                                !resolvedCurrentUser.allowMessages
                                    ? l10n.profileMessagingDisabledSenderMessage
                                    : l10n
                                          .profileMessagingDisabledRecipientMessage,
                              );
                              return;
                            }

                            final existingConversationId = await chatController
                                .findExistingConversationId(
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
                                      title: l10n.selectUserContactContextTitle,
                                    ),
                                  ),
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                );

                            if (draft == null) {
                              return;
                            }

                            final result = await chatController
                                .startGuidedConversation(
                                  currentUser: resolvedCurrentUser,
                                  otherUser: user,
                                  context: draft.context,
                                  contactReason: draft.reasonCode,
                                  introMessage: draft.introMessage,
                                );

                            if (result.createdIntake) {
                              AdFeedback.info(
                                l10n.profileContactRecordedTitle,
                                l10n.profileContactRecordedMessage,
                              );
                            }

                            final conversationId = result.conversationId.trim();
                            if (conversationId.isEmpty) {
                              AdFeedback.error(
                                l10n.profileMessagingErrorTitle,
                                l10n.selectUserConversationUnavailableMessage,
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
                              l10n.profileMessagingErrorTitle,
                              error.message,
                            );
                          } catch (_) {
                            AdFeedback.error(
                              l10n.profileMessagingErrorTitle,
                              l10n.selectUserStartConversationFailedMessage,
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
    final initial = user.nom.trim().isNotEmpty
        ? user.nom.trim()[0].toUpperCase()
        : '?';

    return AdSurfaceCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AdRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AdRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(AdSpacing.md),
            child: Row(
              children: [
                AdAvatar(
                  radius: 26,
                  backgroundColor: cs.surfaceContainerHighest,
                  photoUrl: user.photoProfil,
                  fallback: Text(
                    initial,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.nom,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          // Le badge suit le nom plutot que de le remplacer :
                          // Flexible sur le nom, badge a taille fixe, donc un
                          // nom long s'ellipse et le badge reste lisible.
                          if (showsAgencyBadge(user)) ...[
                            const SizedBox(width: 6),
                            const AdAgencyBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.role.isNotEmpty
                            ? user.role
                            : AppLocalizations.of(context)!.selectUserNoRoleLabel,
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
      ),
    );
  }
}
