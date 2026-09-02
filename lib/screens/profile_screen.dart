// lib/screens/profile_screen.dart
import 'dart:async';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:adfoot/widgets/ad_avatar.dart';
import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/models/player_football_profile.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/screens/profil_video_scrollview.dart';
import 'package:adfoot/widgets/contact_intake_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/chat_screen.dart';
import 'package:adfoot/screens/edit_advanced_profile_screen.dart';
import 'package:adfoot/screens/edit_profil_screen.dart';
import 'package:adfoot/screens/setting_screen.dart';
import 'package:adfoot/screens/follow_list_screen.dart';
import 'package:adfoot/widgets/ad_agency_badge.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_profile_cards.dart';
import 'package:adfoot/videos/video_manager.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/utils/country_codes.dart';
import 'package:adfoot/utils/video_ui_strings.dart';

part 'profile_screen_widgets.dart';

String _profileRoleLabel(AppUser user) {
  switch (user.role) {
    case 'joueur':
      return 'Joueur';
    case 'coach':
      return 'Coach';
    case 'club':
      return 'Club';
    case 'recruteur':
      return 'Recruteur';
    case 'agent':
      return 'Agent';
    case 'fan':
      return 'Supporter';
    default:
      return user.role;
  }
}

/// Une date de fin de contrat, telle qu'on l'ecrit sur une fiche.
///
/// Locale, parce que ce fichier n'importe aucun paquet de date et qu'une seule
/// date y est rendue : ajouter `intl` ici couterait plus que ces trois lignes.
String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String _profileInitials(AppUser user) {
  final parts = user.nom
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }

  final first = parts.first.characters.first.toUpperCase();
  final second = parts.length > 1
      ? parts.last.characters.first.toUpperCase()
      : '';
  return '$first$second';
}

class _ProfileLevelStyle {
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final IconData icon;

  const _ProfileLevelStyle({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.icon,
  });
}

_ProfileLevelStyle _profileLevelStyle(String label) {
  switch (label) {
    // Le badge des joueurs que l'agence porte a ses frais. Volontairement
    // sans date ni reference : l'echeance et la reference du dossier sont des
    // informations commerciales internes, et ce badge est vu par les
    // visiteurs du profil autant que par son titulaire.
    case kAgencyPlayerBadgeLabel:
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.brand,
        foregroundColor: AdColors.brandOn,
        borderColor: AdColors.brand,
        icon: Icons.workspace_premium_rounded,
      );
    case 'Profil Elite':
    case 'Profil Élite':
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.tierElite,
        foregroundColor: Colors.white,
        borderColor: AdColors.tierElite,
        icon: Icons.verified_rounded,
      );
    case 'Profil avancé':
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.accent,
        foregroundColor: Colors.white,
        borderColor: AdColors.accent,
        icon: Icons.auto_awesome_rounded,
      );
    case 'Vérifié par Adfoot':
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.tierVerified,
        foregroundColor: Colors.white,
        borderColor: AdColors.tierVerified,
        icon: Icons.verified_rounded,
      );
    case 'Profil complet':
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.success,
        foregroundColor: Colors.white,
        borderColor: AdColors.success,
        icon: Icons.check_circle_rounded,
      );
    default:
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.tierDefaultBg,
        foregroundColor: AdColors.tierDefaultFg,
        borderColor: AdColors.tierDefaultBorder,
        icon: Icons.info_rounded,
      );
  }
}

class ProfileScreen extends StatefulWidget {
  final String uid;
  final bool isReadOnly;

  const ProfileScreen({super.key, required this.uid, this.isReadOnly = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Palette officielle
  static const kPrimary = AdColors.brand;
  static const kSurface = AdColors.surface;

  bool _isFollowActionLoading = false;
  bool _isMessageActionLoading = false;

  late final ProfileController _profileController;
  final AuthController _authController = Get.find<AuthController>();
  final FollowController _followController = Get.find<FollowController>();
  final ChatController _chatController = Get.find<ChatController>();
  final ImagePicker _imagePicker = ImagePicker();
  final VideoManager _videoManager = VideoManager();
  final ScrollController _scrollController = ScrollController();

  static const int _visibleWindowSize = 25;
  static const int _maxLoadedVideos = 100;

  DateTime? _lastFetchAttemptAt;
  static const Duration _fetchThrottle = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _profileController = FeatureControllerRegistry.ensureProfileController(
      widget.uid,
    );
    _profileController.updateUserId(widget.uid);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final now = DateTime.now();
    if (_lastFetchAttemptAt != null &&
        now.difference(_lastFetchAttemptAt!) < _fetchThrottle) {
      return;
    }

    _lastFetchAttemptAt = now;

    final nearBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200;

    if (nearBottom &&
        !_profileController.isLoadingVideos &&
        _profileController.hasMoreVideos &&
        _profileController.videoList.length < _maxLoadedVideos) {
      _profileController.fetchUserVideos(widget.uid);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    final ctx = 'profile:${widget.uid}';
    _profileController.pauseAll();
    _videoManager.disposeAllForContext(ctx);
    _scrollController.dispose();
    FeatureControllerRegistry.releaseProfileController(widget.uid);
    super.dispose();
  }

  List<Video> _getVisibleVideos(List<Video> full) {
    if (full.length <= _visibleWindowSize) return full;
    return full.take(_visibleWindowSize).toList(growable: false);
  }

  /// Explains why tapping this tile did not open the player.
  ///
  /// Only reachable on the owner's own profile — nobody else is served a
  /// non-live video (see ProfileRepository.fetchUserVideos).
  void _notifyVideoNotPlayable(Video video) {
    switch (video.lifecycle) {
      case VideoLifecycle.live:
        return;
      case VideoLifecycle.processing:
        AdFeedback.info(
          VideoUiStrings.videoStateProcessing,
          VideoUiStrings.videoNotPlayableProcessing,
        );
      case VideoLifecycle.underReview:
        AdFeedback.info(
          VideoUiStrings.videoStateUnderReview,
          VideoUiStrings.videoNotPlayableUnderReview,
        );
      case VideoLifecycle.moderated:
        AdFeedback.error(
          VideoUiStrings.videoStateModerated,
          VideoUiStrings.videoNotPlayableModerated,
        );
      case VideoLifecycle.failed:
        AdFeedback.error(
          VideoUiStrings.videoStateFailed,
          VideoUiStrings.videoNotPlayableFailed,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ProfileController>(
      tag: widget.uid,
      builder: (controller) {
        if (controller.user == null) {
          return _buildProfileLoadState(controller);
        }

        final user = controller.user!;
        final currentUid = _authController.currentUid;
        final isOwnProfile = currentUid != null && currentUid == user.uid;
        final canMessage = _canSendMessage(user);
        final canViewProfile = isOwnProfile || user.profilePublic;
        final visibleVideos = _getVisibleVideos(controller.videoList);

        if (!canViewProfile) {
          return _buildPrivateProfile(
            user,
            isOwnProfile: isOwnProfile,
            canMessage: canMessage,
          );
        }

        return Scaffold(
          backgroundColor: kSurface,
          appBar: AdAppBar(
            title: user.nom.isNotEmpty ? user.nom : 'Profil',
            subtitle: _profileRoleLabel(user),
            showBottomDivider: true,
            actions: [
              // Settings live here now, not in the navigation bar.
              //
              // "Outils" — Compte, Confidentialité, Sécurité, Suppression —
              // was a top-level destination while the profile was not, which
              // is backwards: settings are visited rarely, a profile
              // constantly. They swapped places, and this is the one tap that
              // still reaches them.
              //
              // The link is one-way on purpose. Outils used to open a second
              // full copy of the profile — same header, same editors, same
              // "Compléter le profil" — so the same fields could be reached
              // by two routes and the settings screen had to carry the
              // account's name and e-mail to make its own header look right.
              // Everything about the profile is now on this screen and only
              // on it; Outils owns the session, privacy, safety and deletion,
              // and nothing else.
              if (isOwnProfile && !widget.isReadOnly)
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Outils',
                  onPressed: () => unawaited(Get.to(() => SettingsScreen())),
                ),
              if (isOwnProfile && !widget.isReadOnly)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final updated = await Get.to<bool>(
                      () => EditProfileScreen(
                        user: user,
                        profileController: _profileController,
                      ),
                    );
                    if (updated == true) {
                      _profileController.update();
                    }
                  },
                )
              else if (!isOwnProfile && currentUid != null)
                IconButton(
                  icon: const Icon(Icons.message),
                  onPressed: canMessage && !_isMessageActionLoading
                      ? () => _handleSendMessage(user)
                      : null,
                ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              color: kPrimary,
              onRefresh: () => controller.refreshProfileVideos(),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _HeaderCard(
                        user: user,
                        isOwnProfile: isOwnProfile,
                        isReadOnly: widget.isReadOnly,
                        onViewPhoto: () =>
                            _showFullProfilePhoto(user.photoProfil, user.uid),
                        onChangePhoto: () => _changeProfilePhoto(user.uid),
                        profileController: _profileController,
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _buildNetworkStatsCard(user),
                    ),
                  ),

                  if (!isOwnProfile)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: _buildFollowMessageRow(
                          user,
                          canMessage: canMessage,
                        ),
                      ),
                    ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: AdSectionCard(
                        title: _bioSectionTitle(user),
                        icon: Icons.notes_rounded,
                        child: Text(
                          user.bio?.isNotEmpty == true
                              ? user.bio!
                              : _emptyBioMessage(user),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),

                  // Badge niveau + CTA avance
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(children: [_buildProfileLevelBadge(user)]),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _buildAdvancedCtaIfNeededClean(
                        user,
                        isOwnProfile: isOwnProfile,
                      ),
                    ),
                  ),

                  // 1) Profil public
                  if (!user.isFan)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: AdSectionCard(
                          title: _publicSectionTitleClean(user),
                          icon: Icons.sports_soccer_outlined,
                          child: _buildBaseFootballSectionClean(
                            user,
                            isOwnProfile: isOwnProfile,
                          ),
                        ),
                      ),
                    ),

                  // 2) Informations avancees
                  if (user.shouldShowAdvancedSection)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: AdSectionCard(
                          title: _advancedSectionTitleClean(user),
                          icon: Icons.auto_awesome_rounded,
                          child: _buildAdvancedFootballSectionClean(
                            user,
                            isOwnProfile: isOwnProfile,
                          ),
                        ),
                      ),
                    ),

                  // 3) Documents et preuves
                  if (_shouldShowEvidenceSection(user))
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: AdSectionCard(
                          title: 'Documents et preuves',
                          icon: Icons.folder_open_rounded,
                          child: _buildEvidenceSectionClean(user),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  if (user.role == 'joueur') ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: _SectionHeader(
                          icon: Icons.video_collection_outlined,
                          title: 'Vidéos',
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 9 / 16,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          if (index >= visibleVideos.length) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final video = visibleVideos[index];

                          return _VideoTile(
                            video: video,
                            onTap: () async {
                              // The grid now also lists the owner's videos
                              // that are still processing or awaiting admin
                              // approval. Those have no playable asset (or no
                              // clearance to play one), so they must never
                              // reach the player — and the index handed to it
                              // has to be recomputed against the playable
                              // subset, not the grid position.
                              if (!video.isPlayable) {
                                _notifyVideoNotPlayable(video);
                                return;
                              }

                              final playableVideos = visibleVideos
                                  .where((item) => item.isPlayable)
                                  .toList(growable: false);
                              final playableIndex = playableVideos.indexWhere(
                                (item) => item.id == video.id,
                              );
                              if (playableIndex < 0) {
                                return;
                              }

                              final contextKey = 'profile:${widget.uid}';
                              final videoController =
                                  FeatureControllerRegistry.ensureVideoController(
                                    contextKey: contextKey,
                                    enableLiveStream: false,
                                    enableFeedFetch: false,
                                    permanent: true,
                                  );

                              await _profileController.pauseAll();

                              videoController.replaceVideos(
                                playableVideos,
                                selectedIndex: playableIndex,
                              );

                              await Get.to(
                                () => ProfileVideoScrollView(
                                  videos: playableVideos,
                                  initialIndex: playableIndex,
                                  uid: widget.uid,
                                  contextKey: contextKey,
                                ),
                              );

                              // Un seul propriétaire par contexte : c'est
                              // ProfileVideoScrollView qui crée les lecteurs
                              // (via son VideoFocusOrchestrator) et qui les
                              // détruit dans son `dispose`. La grille, elle,
                              // n'affiche que des images. Détruire une
                              // seconde fois ici ne faisait que masquer la
                              // question de savoir à qui appartient le
                              // contexte ; `VideoController.onClose` reste le
                              // filet, déclenché par le release ci-dessous
                              // quand plus personne ne tient la référence.
                              FeatureControllerRegistry.releaseVideoController(
                                contextKey,
                              );
                            },
                          );
                        }, childCount: visibleVideos.length),
                      ),
                    ),
                    if (controller.isLoadingVideos && controller.hasMoreVideos)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileLoadState(ProfileController controller) {
    // Only spin while a load is genuinely running. Reaching this state with
    // no load in flight and no attempt behind it used to leave a spinner that
    // nothing would ever replace; re-arm the load instead so the screen
    // always converges on a profile or on an actionable error.
    if (controller.isLoadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!controller.hasAttemptedProfileLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(controller.updateUserId(widget.uid));
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final errorMessage =
        (controller.profileLoadErrorMessage?.trim().isNotEmpty ?? false)
        ? controller.profileLoadErrorMessage!
        : 'Chargement du profil impossible. Réessayez dans quelques instants.';

    return Scaffold(
      backgroundColor: kSurface,
      appBar: const AdAppBar(title: 'Profil', showBottomDivider: true),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  size: 56,
                  color: AdColors.onSurfaceMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  controller.profileLoadErrorTitle ?? 'Profil indisponible',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AdColors.onSurfaceMuted),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: controller.isLoadingUser
                      ? null
                      : () => controller.updateUserId(widget.uid),
                  icon: controller.isLoadingUser
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =======================
  // Actions
  // =======================

  bool _canSendMessage(AppUser user) {
    final currentUser = Get.find<UserController>().user ?? _authController.user;
    if (currentUser == null) return false;
    return currentUser.allowMessages && user.allowMessages;
  }

  void _showMessagingDisabledNotice(AppUser user) {
    final currentUser = Get.find<UserController>().user ?? _authController.user;
    if (currentUser == null) return;

    final isSenderDisabled = !currentUser.allowMessages;
    final isRecipientDisabled = !user.allowMessages;

    String message;
    if (isSenderDisabled && isRecipientDisabled) {
      message = 'Les messages sont désactivés pour vous deux.';
    } else if (isSenderDisabled) {
      message = 'Vous avez désactivé l’envoi de messages.';
    } else {
      message = 'Cet utilisateur a désactivé les messages.';
    }

    AdFeedback.warning('Messages indisponibles', message);
  }

  Future<void> _handleSendMessage(AppUser user) async {
    if (_isMessageActionLoading) {
      return;
    }

    final currentUser = Get.find<UserController>().user ?? _authController.user;
    final currentUserId = currentUser?.uid ?? _authController.currentUid;
    if (currentUser == null || currentUserId == null) {
      AdFeedback.error('Session invalide', 'Utilisateur non connecté.');
      return;
    }

    if (!_canSendMessage(user)) {
      _showMessagingDisabledNotice(user);
      return;
    }

    setState(() => _isMessageActionLoading = true);
    try {
      final existingConversationId = await _chatController
          .findExistingConversationId(
            currentUserId: currentUserId,
            otherUserId: user.uid,
          );

      if (existingConversationId != null && existingConversationId.isNotEmpty) {
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

      if (!mounted) {
        return;
      }

      final draft = await Get.bottomSheet<GuidedContactDraft>(
        ContactIntakeSheet(
          currentUser: currentUser,
          otherUser: user,
          context: ContactContext.profile(
            profileUid: user.uid,
            title: user.nom,
          ),
        ),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );

      if (draft == null) {
        return;
      }

      final result = await _chatController.startGuidedConversation(
        currentUser: currentUser,
        otherUser: user,
        context: draft.context,
        contactReason: draft.reasonCode,
        introMessage: draft.introMessage,
      );

      final conversationId = result.conversationId;
      if (result.createdIntake) {
        AdFeedback.info(
          'Contact enregistré',
          'Le premier contact a été cadré et transmis via Adfoot.',
        );
      }

      if (conversationId.isEmpty) {
        AdFeedback.error(
          'Erreur',
          'Impossible d’ouvrir la messagerie pour le moment.',
        );
        return;
      }

      if (!mounted) {
        return;
      }

      await Get.to(
        () => ChatScreen(conversationId: conversationId, otherUser: user),
      );
    } on ChatFlowException catch (error) {
      AdFeedback.error('Erreur', error.message);
    } catch (_) {
      AdFeedback.error(
        'Erreur',
        'Impossible d’ouvrir la messagerie pour le moment.',
      );
    } finally {
      if (mounted) {
        setState(() => _isMessageActionLoading = false);
      }
    }
  }

  Widget _buildPrivateProfile(
    AppUser user, {
    required bool isOwnProfile,
    required bool canMessage,
  }) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AdAppBar(
        title: user.nom.isNotEmpty ? user.nom : 'Profil',
        subtitle: _profileRoleLabel(user),
        showBottomDivider: true,
        actions: [
          if (!isOwnProfile && _authController.currentUid != null)
            IconButton(
              icon: const Icon(Icons.message),
              onPressed: canMessage && !_isMessageActionLoading
                  ? () => _handleSendMessage(user)
                  : null,
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: kPrimary),
              const SizedBox(height: 12),
              const Text(
                'Profil privé',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Ce profil n’est pas visible pour le moment.",
                style: TextStyle(color: AdColors.onSurfaceMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (canMessage)
                AdButton(
                  onPressed: _isMessageActionLoading
                      ? null
                      : () => _handleSendMessage(user),
                  loading: _isMessageActionLoading,
                  leading: Icons.message_outlined,
                  label: 'Contacter',
                  expanded: false,
                )
              else
                Text(
                  'La messagerie est désactivée pour cet utilisateur.',
                  style: TextStyle(color: AdColors.onSurfaceMuted),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullProfilePhoto(String photoUrl, String uid) {
    if (photoUrl.isEmpty) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer la photo de profil', // Obligatoire
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Center(
                child: Hero(
                  tag: 'profile-photo-$uid',
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white,
                          size: 64,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _changeProfilePhoto(String uid) async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      try {
        await _profileController.updateProfilePhoto(uid, file.path);
      } on ProfileAccessRevokedException {
        return;
      }
    }
  }

  // =======================
  // UI helpers (MVP / Avance)
  // =======================

  Widget _buildProfileLevelBadge(AppUser user) {
    final style = _profileLevelStyle(user.profileLevelLabel);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.foregroundColor, size: 18),
          const SizedBox(width: 8),
          Text(
            user.profileLevelLabel,
            style: TextStyle(
              color: style.foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedCtaIfNeededClean(
    AppUser user, {
    required bool isOwnProfile,
  }) {
    if (!isOwnProfile) return const SizedBox.shrink();
    if (user.isFan) return const SizedBox.shrink();

    final hasAdvancedProfile = user.hasAdvancedProfile;
    final message = hasAdvancedProfile
        ? user.isPlayer
              ? 'Gardez votre dossier scout à jour pour que les recruteurs disposent d’informations fiables.'
              : user.isClub
              ? 'Maintenez la présentation de votre club, vos catégories et vos besoins à jour.'
              : user.isRecruiter
              ? user.isAgent
                    ? 'Maintenez votre cadre de représentation, votre licence et vos zones à jour.'
                    : 'Maintenez vos références professionnelles et vos zones d’intervention à jour.'
              : 'Gardez les informations avancées du profil à jour.'
        : user.isPlayer
        ? 'Complétez votre fiche joueur et votre dossier scout pour présenter un profil plus crédible aux clubs et recruteurs.'
        : user.isClub
        ? 'Complétez la présentation de votre club pour afficher clairement votre structure, vos catégories et vos besoins.'
        : user.isRecruiter
        ? user.isAgent
              ? 'Complétez votre cadre de représentation pour présenter votre agence, votre licence et vos zones d’intervention.'
              : 'Complétez vos références professionnelles pour présenter votre structure, vos licences et vos zones d’intervention.'
        : 'Complétez les informations avancées du profil.';

    Future<void> openAdvancedEditor() async {
      if (user.isPlayer || user.isClub || user.isRecruiter) {
        final updated = await Get.to<bool>(
          () => EditAdvancedProfileScreen(
            user: user,
            profileController: _profileController,
          ),
        );
        if (updated == true) {
          _profileController.update();
        }
      }
    }

    Widget buildActionButton({double? width}) {
      return SizedBox(
        width: width,
        child: AdButton(
          onPressed: () => openAdvancedEditor(),
          leading: hasAdvancedProfile
              ? Icons.edit_outlined
              : Icons.add_circle_outline_rounded,
          label: hasAdvancedProfile ? 'Mettre à jour' : 'Compléter',
          expanded: width == null,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icon = Icon(
            hasAdvancedProfile
                ? Icons.manage_search_outlined
                : Icons.lightbulb_outline_rounded,
            color: kPrimary,
          );
          final text = Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w600),
          );

          if (constraints.maxWidth < 380) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 10),
                    Expanded(child: text),
                  ],
                ),
                const SizedBox(height: 12),
                buildActionButton(width: double.infinity),
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(child: text),
              const SizedBox(width: 10),
              buildActionButton(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNetworkStatsCard(AppUser user) {
    return AdSectionCard(
      title: 'Réseau',
      icon: Icons.people_outline,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatChip(
            label: 'Abonnés',
            value: user.followersList.length,
            onTap: () => Get.to(
              () => FollowListScreen(uid: user.uid, listType: 'followers'),
            ),
          ),
          _StatChip(
            label: 'Abonnements',
            value: user.followingsList.length,
            onTap: () => Get.to(
              () => FollowListScreen(uid: user.uid, listType: 'followings'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaseFootballSectionClean(
    AppUser user, {
    required bool isOwnProfile,
  }) {
    final tiles = <Widget>[];
    final location = [
      user.city,
      user.region,
      user.country,
    ].where((value) => value?.trim().isNotEmpty == true).join(', ');

    // phone lives in users/{uid}/private/contact and is only fetched for the
    // profile owner — this guard is defense in depth, not the only thing
    // stopping a visitor from seeing it.
    if (isOwnProfile) {
      tiles.add(_infoTile('Téléphone', user.phone, icon: Icons.phone_outlined));
    }

    if (user.languages != null && user.languages!.isNotEmpty) {
      tiles.add(
        _infoTile(
          'Langues parlées',
          user.languages!.join(', '),
          icon: Icons.language_outlined,
        ),
      );
    }

    if (location.isNotEmpty) {
      tiles.add(
        _infoTile('Localisation', location, icon: Icons.place_outlined),
      );
    }

    if (user.isPlayer || user.isCoach) {
      // Le club type d'abord. Les deux anciens champs restent en secours pour
      // les comptes crees avant la bascule : ils ne sont plus ecrits par
      // aucune surface, et le premier enregistrement du profil les convertit.
      final teamLabel =
          user.football.currentClubName ?? user.team ?? user.clubActuel;

      // Le poste tel qu'un recruteur le filtre, et non tel qu'il a ete tape.
      // Le coach garde son texte libre : sa fonction n'a pas d'equivalent
      // dans la liste fermee des postes de terrain.
      final positionLabel = user.isCoach
          ? user.position
          : (user.football.positions.isEmpty
                ? null
                : user.football.positions
                      .map((position) => position.labelFr)
                      .join(' · '));
      tiles.addAll([
        // L'annee derivee, pas l'age calcule depuis `birthDate`.
        //
        // `birthDate` vit dans `private/contact` et n'atteint que le
        // titulaire : cette tuile affichait donc « 18 ans » au joueur et rien
        // du tout au recruteur, sur la meme fiche. `birthYear` est pose par le
        // serveur sur le document public, donc les deux lecteurs voient la
        // meme chose.
        //
        // L'annee est aussi la bonne unite : les categories du football se
        // comptent par annee de naissance, pas par age au jour pres.
        _infoTile(
          'Année de naissance',
          user.football.birthYear?.toString(),
          icon: Icons.cake_outlined,
        ),
        _infoTile(
          user.isCoach ? 'Fonction sportive' : 'Postes',
          positionLabel,
          icon: Icons.sports_outlined,
        ),
        _infoTile(
          user.isCoach ? 'Club / structure' : 'Club actuel',
          teamLabel,
          icon: Icons.flag_outlined,
        ),
      ]);
    } else if (user.isClub) {
      tiles.addAll([
        _infoTile(
          'Ligue / championnat',
          user.ligue,
          icon: Icons.emoji_events_outlined,
        ),
      ]);
    } else if (user.isRecruiter) {
      tiles.addAll([
        _infoTile(
          user.isAgent ? 'Agence / structure' : 'Structure de recrutement',
          user.entreprise,
          icon: Icons.business_outlined,
        ),
        _infoTile(
          user.isAgent
              ? 'Placements ou signatures réalisés'
              : 'Recrutements réalisés',
          user.nombreDeRecrutements?.toString(),
          icon: Icons.how_to_reg_outlined,
        ),
      ]);
    } else {
      tiles.add(_infoTile('Informations', 'Aucune information renseignée.'));
    }

    return Column(children: tiles);
  }

  String _bioSectionTitle(AppUser user) {
    if (user.isPlayer) return 'Présentation du joueur';
    if (user.isCoach) return 'Présentation du coach';
    if (user.isClub) return 'Présentation du club';
    if (user.isRecruiter) {
      return user.isAgent
          ? 'Présentation de l’agent'
          : 'Présentation du recruteur';
    }
    return 'Présentation';
  }

  String _emptyBioMessage(AppUser user) {
    if (user.isPlayer) return 'Aucune présentation de joueur renseignée.';
    if (user.isCoach) return 'Aucune présentation de coach renseignée.';
    if (user.isClub) return 'Aucune présentation de club renseignée.';
    if (user.isRecruiter) {
      return user.isAgent
          ? 'Aucune présentation d’agent renseignée.'
          : 'Aucune présentation de recruteur renseignée.';
    }
    return 'Aucune présentation renseignée.';
  }

  Widget _buildAdvancedFootballSectionClean(
    AppUser user, {
    required bool isOwnProfile,
  }) {
    if (!user.hasAdvancedProfile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aucune information avancée n’a encore été renseignée.',
            style: TextStyle(color: AdColors.onSurfaceMuted),
          ),
          const SizedBox(height: 8),
          Text(
            user.isPlayer
                ? 'Ajoutez le gabarit, les postes, les statistiques et la disponibilité du joueur.'
                : user.isClub
                ? 'Ajoutez la structure du club, les catégories et les besoins de recrutement.'
                : user.isRecruiter
                ? user.isAgent
                      ? 'Ajoutez votre licence, votre pays de délivrance et vos zones de représentation.'
                      : 'Ajoutez vos références de licence et vos zones d’intervention.'
                : 'Complétez les informations avancées du profil.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    if (user.isPlayer) {
      final football = user.football;
      final season = football.currentSeason;

      String? countLabel(int? value, String unit) =>
          value == null ? null : '$value $unit';

      return Column(
        children: [
          // L'identite footballistique d'abord : c'est ce qu'un recruteur lit
          // en premier, et le reste ne l'interesse que si celle-ci lui parle.
          // Les postes et le club actuel ne sont plus repris ici : ils sont
          // affiches une fois, avec le reste de l'identite, dans la section du
          // dessus. Ce qui reste ici est ce qu'elle ne porte pas.
          _infoTile(
            'Pied fort',
            football.strongFoot?.labelFr,
            icon: Icons.sports_soccer_outlined,
          ),
          _infoTile(
            'Taille',
            countLabel(football.heightCm, 'cm'),
            icon: Icons.height_outlined,
          ),
          _infoTile(
            'Poids',
            countLabel(football.weightKg, 'kg'),
            icon: Icons.monitor_weight_outlined,
          ),
          _infoTile(
            'Nationalités',
            football.nationalities.isEmpty
                ? null
                : football.nationalities.map(countryLabel).join(' · '),
            icon: Icons.public_outlined,
          ),
          // L'annee de naissance n'est plus reprise ici : elle est affichee
          // une fois, avec le reste de l'identite, dans la section du dessus.
          const Divider(),
          _infoTile(
            'Niveau',
            football.currentClubLevel?.labelFr,
            icon: Icons.stairs_outlined,
          ),
          _infoTile(
            'Statut',
            football.contractStatus?.labelFr,
            icon: Icons.assignment_outlined,
          ),
          _infoTile(
            'Fin de contrat',
            football.contractStatus?.expectsEndDate == true &&
                    football.contractEndDate != null
                ? _formatDate(football.contractEndDate!)
                : null,
            icon: Icons.event_outlined,
          ),
          const Divider(),
          _infoTile(
            'Saison',
            [
              season?.season,
              season?.competition,
              season?.ageCategory?.code,
            ].whereType<String>().join(' · ').trim().isEmpty
                ? null
                : [
                    season?.season,
                    season?.competition,
                    season?.ageCategory?.code,
                  ].whereType<String>().join(' · '),
            icon: Icons.calendar_month_outlined,
          ),
          _infoTile(
            'Matchs joués',
            season?.appearances?.toString(),
            icon: Icons.numbers_outlined,
          ),
          _infoTile(
            'Temps de jeu',
            countLabel(season?.minutes, 'min'),
            icon: Icons.timer_outlined,
          ),
          _infoTile(
            'Buts inscrits',
            season?.goals?.toString(),
            icon: Icons.sports_score_outlined,
          ),
          _infoTile(
            'Passes décisives',
            season?.assists?.toString(),
            icon: Icons.assistant_direction_outlined,
          ),

          // Le parcours, sous la saison en cours : c'est la lecture d'un
          // recruteur, du present vers ce qui y a mene. Une seule saison ne
          // dit pas si un joueur progresse.
          if (football.seasonHistory.isNotEmpty) ...[
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Parcours',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 6),
            for (final archived in football.seasonHistory)
              _infoTile(
                [
                  ?archived.season,
                  ?archived.clubName,
                ].join(' · '),
                _pastSeasonSummary(archived),
                icon: Icons.history_rounded,
              ),
          ],

          const Divider(),
          _infoTile(
            'Ouvert aux opportunités',
            user.openToOpportunities == null
                ? null
                : (user.openToOpportunities == true ? 'Oui' : 'Non'),
            icon: Icons.travel_explore,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              user.hasScoutReadyProfile
                  ? 'Dossier scout prêt'
                  : 'Dossier scout partiel',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: user.hasScoutReadyProfile
                    ? AdColors.success
                    : AdColors.warning,
              ),
            ),
          ),
          // Ce qui manque, et seulement pour le titulaire du profil.
          //
          // « Partiel » sans dire de quoi laissait le joueur deviner : c'est
          // la difference entre un constat et une action. La liste vient de
          // `missingScoutRequirements`, donc elle ne peut pas reclamer autre
          // chose que ce que la regle exige.
          //
          // Un visiteur ne la voit pas : pour un recruteur c'est du bruit, et
          // pour le joueur c'est une liste de ce qui lui manque affichee a
          // des inconnus.
          if (isOwnProfile && !user.hasScoutReadyProfile)
            _MissingScoutRequirements(
              missing: user.missingScoutRequirements,
            ),
        ],
      );
    }

    if (user.isClub) {
      final club = user.club;

      return Column(
        children: [
          _infoTile(
            'Niveau de la structure',
            club.level?.labelFr,
            icon: Icons.account_tree_outlined,
          ),
          _infoTile(
            'Catégories engagées',
            club.ageCategories.isEmpty
                ? null
                : club.ageCategories.map((c) => c.labelFr).join(' · '),
            icon: Icons.groups_2_outlined,
          ),
          // Les besoins de recrutement ne sont plus ici : ils vivent dans les
          // offres, qui sont datees, moderees et candidatables. Deux sources
          // pour un seul fait finissent par se contredire.
          _infoTile(
            'Numéro d’affiliation',
            club.federationId,
            icon: Icons.badge_outlined,
          ),
        ],
      );
    }

    if (user.isRecruiter) {
      final agent = user.agent;

      return Column(
        children: [
          _infoTile(
            user.isAgent
                ? 'Numéro de licence'
                : 'Référence de licence ou d’agrément',
            agent.licenceNumber,
            icon: Icons.badge_outlined,
          ),
          _infoTile(
            'Fédération émettrice',
            agent.licenceCountry == null
                ? null
                : countryLabel(agent.licenceCountry),
            icon: Icons.flag_circle_outlined,
          ),
          _infoTile(
            user.isAgent ? 'Pays de représentation' : 'Pays d’intervention',
            agent.countries.isEmpty
                ? null
                : agent.countries.map(countryLabel).join(' · '),
            icon: Icons.public_outlined,
          ),
        ],
      );
    }

    return const Text('Aucun profil avancé pour ce rôle.');
  }

  Widget _buildEvidenceSectionClean(AppUser user) {
    final tiles = <Widget>[];

    if (user.isPlayer) {
      if (user.cvUrl != null) {
        tiles.add(
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Voir le CV'),
              subtitle: const Text('CV au format PDF'),
              onTap: () async {
                final uri = Uri.parse(user.cvUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        );
      } else {
        tiles.add(
          const Material(
            color: Colors.transparent,
            child: ListTile(
              leading: Icon(Icons.picture_as_pdf_outlined),
              title: Text('CV'),
              subtitle: Text('Aucun CV renseigné'),
            ),
          ),
        );
      }
    }

    return Column(children: tiles);
  }

  String _publicSectionTitleClean(AppUser user) {
    if (user.isPlayer) return 'Fiche joueur';
    if (user.isCoach) return 'Profil coach';
    if (user.isClub) return 'Présentation du club';
    if (user.isRecruiter) {
      return user.isAgent
          ? 'Références de représentation'
          : 'Références professionnelles';
    }
    return 'Profil public';
  }

  String _advancedSectionTitleClean(AppUser user) {
    if (user.isPlayer) return 'Dossier scout';
    if (user.isClub) return 'Structure et recrutement';
    if (user.isRecruiter) {
      return user.isAgent
          ? 'Licence et zones de représentation'
          : 'Licence et zones d’intervention';
    }
    return 'Informations avancées';
  }


  Widget _buildFollowMessageRow(AppUser user, {required bool canMessage}) {
    final currentUserId = _authController.currentUid;
    if (currentUserId == null) {
      return const SizedBox.shrink();
    }

    final bool isFollowing = user.followersList.contains(currentUserId);

    return Row(
      children: [
        Expanded(
          child: AdButton(
            leading: isFollowing
                ? Icons.person_remove_alt_1
                : Icons.person_add_alt,
            label: isFollowing ? 'Se désabonner' : 'S’abonner',
            kind: isFollowing ? AdButtonKind.outline : AdButtonKind.tonal,
            loading: _isFollowActionLoading,
            onPressed: _isFollowActionLoading
                ? null
                : () async {
                    final shouldFollow = !isFollowing;
                    setState(() => _isFollowActionLoading = true);

                    _profileController.applyLocalFollowerChange(
                      currentUserId: currentUserId,
                      shouldFollow: shouldFollow,
                    );

                    try {
                      final ok = isFollowing
                          ? await _followController.unfollowUser(
                              currentUserId,
                              user.uid,
                            )
                          : await _followController.followUser(
                              currentUserId,
                              user.uid,
                            );

                      if (!ok) {
                        _profileController.applyLocalFollowerChange(
                          currentUserId: currentUserId,
                          shouldFollow: isFollowing,
                        );

                        if (_authController.currentUid == null) {
                          return;
                        }

                        AdFeedback.error('Erreur', 'Action impossible.');
                      }
                    } catch (_) {
                      _profileController.applyLocalFollowerChange(
                        currentUserId: currentUserId,
                        shouldFollow: isFollowing,
                      );
                      AdFeedback.error(
                        'Erreur',
                        'Action impossible pour le moment.',
                      );
                    } finally {
                      if (mounted) {
                        setState(() => _isFollowActionLoading = false);
                      }
                    }
                  },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AdButton(
            leading: Icons.message_outlined,
            label: 'Contacter',
            kind: AdButtonKind.tonal,
            loading: _isMessageActionLoading,
            onPressed: canMessage && !_isMessageActionLoading
                ? () => _handleSendMessage(user)
                : null,
          ),
        ),
      ],
    );
  }

  // =======================
  // Sections (Base / Avance / Preuves)
  // =======================

  bool _shouldShowEvidenceSection(AppUser user) {
    // A ce stade, seules les pièces joueur apportent une vraie preuve utile
    // sur le profil public. Les comptes club / recruteur / agent restent plus
    // lisibles sans un bloc vide ou redondant.
    return user.isPlayer;
  }

  /// Ce qu'une saison passee a produit, en une ligne.
  ///
  /// Le niveau du club y figure parce qu'il change tout : « 28 matchs, 11
  /// buts » ne pese pas la meme chose en academie et en premiere division.
  String? _pastSeasonSummary(SeasonRecord season) {
    final parts = <String>[
      ?season.competition,
      ?season.clubLevel?.labelFr,
      ?season.ageCategory?.code,
      if (season.appearances != null) '${season.appearances} matchs',
      if (season.minutes != null) '${season.minutes} min',
      if (season.goals != null) '${season.goals} buts',
      if (season.assists != null) '${season.assists} passes',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _infoTile(String label, String? value, {IconData? icon}) {
    final hasValue = value?.isNotEmpty == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AdColors.surfaceCardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AdColors.brand, size: 20),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  hasValue ? value! : 'Non spécifié',
                  style: TextStyle(
                    color: hasValue
                        ? AdColors.onSurface
                        : AdColors.onSurfaceMuted,
                    fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =======================
// Widgets secondaires
// =======================
