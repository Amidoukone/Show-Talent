// lib/screens/profile_screen.dart
import 'dart:async';

import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:adfoot/l10n/generated/app_localizations.dart';
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

String _profileRoleLabel(AppLocalizations l10n, AppUser user) {
  switch (user.role) {
    case 'joueur':
      return l10n.profileRoleJoueur;
    case 'coach':
      return l10n.profileRoleCoach;
    case 'club':
      return l10n.profileRoleClub;
    case 'recruteur':
      return l10n.profileRoleRecruteur;
    case 'agent':
      return l10n.profileRoleAgent;
    case 'fan':
      return l10n.profileRoleFan;
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

/// What a badge looks like, keyed by a stable identifier -- never by the
/// translated label text, which would tie the visual style to whichever
/// locale happens to be active. See [AppUser.profileLevel] and
/// [AppUser.profileTrustStatus].
enum _ProfileBadgeKind {
  agencyPlayer,
  elite,
  advanced,
  verifiedTrust,
  complete,
  standard,
}

_ProfileBadgeKind _badgeKindForLevel(ProfileLevel level) {
  switch (level) {
    case ProfileLevel.elite:
      return _ProfileBadgeKind.elite;
    case ProfileLevel.advanced:
      return _ProfileBadgeKind.advanced;
    case ProfileLevel.complete:
      return _ProfileBadgeKind.complete;
    case ProfileLevel.basic:
      return _ProfileBadgeKind.standard;
  }
}

_ProfileBadgeKind _badgeKindForTrust(ProfileTrustStatus status) {
  return status == ProfileTrustStatus.verified
      ? _ProfileBadgeKind.verifiedTrust
      : _ProfileBadgeKind.standard;
}

_ProfileLevelStyle _profileLevelStyle(_ProfileBadgeKind kind) {
  switch (kind) {
    // Le badge des joueurs que l'agence porte a ses frais. Volontairement
    // sans date ni reference : l'echeance et la reference du dossier sont des
    // informations commerciales internes, et ce badge est vu par les
    // visiteurs du profil autant que par son titulaire.
    case _ProfileBadgeKind.agencyPlayer:
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.brand,
        foregroundColor: AdColors.brandOn,
        borderColor: AdColors.brand,
        icon: Icons.workspace_premium_rounded,
      );
    case _ProfileBadgeKind.elite:
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.tierElite,
        foregroundColor: Colors.white,
        borderColor: AdColors.tierElite,
        icon: Icons.verified_rounded,
      );
    case _ProfileBadgeKind.advanced:
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.accent,
        foregroundColor: Colors.white,
        borderColor: AdColors.accent,
        icon: Icons.auto_awesome_rounded,
      );
    case _ProfileBadgeKind.verifiedTrust:
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.tierVerified,
        foregroundColor: Colors.white,
        borderColor: AdColors.tierVerified,
        icon: Icons.verified_rounded,
      );
    case _ProfileBadgeKind.complete:
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.success,
        foregroundColor: Colors.white,
        borderColor: AdColors.success,
        icon: Icons.check_circle_rounded,
      );
    case _ProfileBadgeKind.standard:
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
    final l10n = AppLocalizations.of(context)!;
    return GetBuilder<ProfileController>(
      tag: widget.uid,
      builder: (controller) {
        if (controller.user == null) {
          return _buildProfileLoadState(controller, l10n);
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
            l10n,
            isOwnProfile: isOwnProfile,
            canMessage: canMessage,
          );
        }

        return Scaffold(
          backgroundColor: kSurface,
          appBar: AdAppBar(
            title: user.nom.isNotEmpty ? user.nom : l10n.profileFallbackTitle,
            subtitle: _profileRoleLabel(l10n, user),
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
                  tooltip: l10n.settingsAppBarTitle,
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
                      child: _buildNetworkStatsCard(user, l10n),
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
                          l10n,
                          canMessage: canMessage,
                        ),
                      ),
                    ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: AdSectionCard(
                        title: _bioSectionTitle(l10n, user),
                        icon: Icons.notes_rounded,
                        child: Text(
                          user.bio?.isNotEmpty == true
                              ? user.bio!
                              : _emptyBioMessage(l10n, user),
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
                        l10n,
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
                          title: _publicSectionTitleClean(l10n, user),
                          icon: Icons.sports_soccer_outlined,
                          child: _buildBaseFootballSectionClean(
                            user,
                            l10n,
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
                          title: _advancedSectionTitleClean(l10n, user),
                          icon: Icons.auto_awesome_rounded,
                          child: _buildAdvancedFootballSectionClean(
                            user,
                            l10n,
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
                          title: l10n.profileEvidenceSectionTitle,
                          icon: Icons.folder_open_rounded,
                          child: _buildEvidenceSectionClean(user, l10n),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  if (user.role == 'joueur') ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: _SectionHeader(
                          icon: Icons.video_collection_outlined,
                          title: l10n.profileVideosSectionTitle,
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

  Widget _buildProfileLoadState(
    ProfileController controller,
    AppLocalizations l10n,
  ) {
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
        : l10n.profileLoadFailureMessage;

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AdAppBar(
        title: l10n.profileFallbackTitle,
        showBottomDivider: true,
      ),
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
                  controller.profileLoadErrorTitle ??
                      l10n.mainProfileUnavailableTitle,
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
                  label: Text(l10n.commonRetry),
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

    final l10n = AppLocalizations.of(context)!;
    String message;
    if (isSenderDisabled && isRecipientDisabled) {
      message = l10n.profileMessagingDisabledBothMessage;
    } else if (isSenderDisabled) {
      message = l10n.profileMessagingDisabledSenderMessage;
    } else {
      message = l10n.profileMessagingDisabledRecipientMessage;
    }

    AdFeedback.warning(l10n.profileMessagingDisabledTitle, message);
  }

  Future<void> _handleSendMessage(AppUser user) async {
    if (_isMessageActionLoading) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final currentUser = Get.find<UserController>().user ?? _authController.user;
    final currentUserId = currentUser?.uid ?? _authController.currentUid;
    if (currentUser == null || currentUserId == null) {
      AdFeedback.error(
        l10n.profileInvalidSessionTitle,
        l10n.profileNotSignedInMessage,
      );
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
          l10n.profileContactRecordedTitle,
          l10n.profileContactRecordedMessage,
        );
      }

      if (conversationId.isEmpty) {
        AdFeedback.error(
          l10n.profileMessagingErrorTitle,
          l10n.profileMessagingUnavailableMessage,
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
      AdFeedback.error(l10n.profileMessagingErrorTitle, error.message);
    } catch (_) {
      AdFeedback.error(
        l10n.profileMessagingErrorTitle,
        l10n.profileMessagingUnavailableMessage,
      );
    } finally {
      if (mounted) {
        setState(() => _isMessageActionLoading = false);
      }
    }
  }

  Widget _buildPrivateProfile(
    AppUser user,
    AppLocalizations l10n, {
    required bool isOwnProfile,
    required bool canMessage,
  }) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AdAppBar(
        title: user.nom.isNotEmpty ? user.nom : l10n.profileFallbackTitle,
        subtitle: _profileRoleLabel(l10n, user),
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
              Text(
                l10n.profilePrivateTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.profilePrivateMessage,
                style: const TextStyle(color: AdColors.onSurfaceMuted),
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
                  label: l10n.profileContactButton,
                  expanded: false,
                )
              else
                Text(
                  l10n.profileMessagingDisabledForVisitor,
                  style: const TextStyle(color: AdColors.onSurfaceMuted),
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
      barrierLabel: AppLocalizations.of(context)!.profileClosePhotoLabel,
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
    final style = _profileLevelStyle(_badgeKindForLevel(user.profileLevel));

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
    AppUser user,
    AppLocalizations l10n, {
    required bool isOwnProfile,
  }) {
    if (!isOwnProfile) return const SizedBox.shrink();
    if (user.isFan) return const SizedBox.shrink();

    final hasAdvancedProfile = user.hasAdvancedProfile;
    final message = hasAdvancedProfile
        ? user.isPlayer
              ? l10n.profileCtaUpdatePlayerMessage
              : user.isClub
              ? l10n.profileCtaUpdateClubMessage
              : user.isRecruiter
              ? user.isAgent
                    ? l10n.profileCtaUpdateAgentMessage
                    : l10n.profileCtaUpdateRecruiterMessage
              : l10n.profileCtaUpdateDefaultMessage
        : user.isPlayer
        ? l10n.profileCtaCompletePlayerMessage
        : user.isClub
        ? l10n.profileCtaCompleteClubMessage
        : user.isRecruiter
        ? user.isAgent
              ? l10n.profileCtaCompleteAgentMessage
              : l10n.profileCtaCompleteRecruiterMessage
        : l10n.profileCtaCompleteDefaultMessage;

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
          label: hasAdvancedProfile
              ? l10n.profileCtaUpdateButton
              : l10n.profileCtaCompleteButton,
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

  Widget _buildNetworkStatsCard(AppUser user, AppLocalizations l10n) {
    return AdSectionCard(
      title: l10n.profileNetworkSectionTitle,
      icon: Icons.people_outline,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatChip(
            label: l10n.profileFollowersLabel,
            value: user.followersList.length,
            onTap: () => Get.to(
              () => FollowListScreen(uid: user.uid, listType: 'followers'),
            ),
          ),
          _StatChip(
            label: l10n.profileFollowingLabel,
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
    AppUser user,
    AppLocalizations l10n, {
    required bool isOwnProfile,
  }) {
    final fields =
        <({String label, String? value, IconData? icon, bool compact})>[];
    final location = [
      user.city,
      user.region,
      user.country,
    ].where((value) => value?.trim().isNotEmpty == true).join(', ');

    // phone lives in users/{uid}/private/contact and is only fetched for the
    // profile owner — this guard is defense in depth, not the only thing
    // stopping a visitor from seeing it.
    if (isOwnProfile) {
      fields.add(
        _field(
          l10n.profilePhoneLabel,
          user.phone,
          icon: Icons.phone_outlined,
          compact: true,
        ),
      );
    }

    if (user.languages != null && user.languages!.isNotEmpty) {
      fields.add(
        _field(
          l10n.profileLanguagesLabel,
          user.languages!.join(', '),
          icon: Icons.language_outlined,
        ),
      );
    }

    if (location.isNotEmpty) {
      fields.add(
        _field(l10n.profileLocationLabel, location, icon: Icons.place_outlined),
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
      fields.addAll([
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
        _field(
          l10n.profileBirthYearLabel,
          user.football.birthYear?.toString(),
          icon: Icons.cake_outlined,
          compact: true,
        ),
        _field(
          user.isCoach
              ? l10n.profileCoachRoleLabel
              : l10n.profilePositionsLabel,
          positionLabel,
          icon: Icons.sports_outlined,
        ),
        _field(
          user.isCoach
              ? l10n.profileCoachClubLabel
              : l10n.profileCurrentClubLabel,
          teamLabel,
          icon: Icons.flag_outlined,
        ),
      ]);
    } else if (user.isClub) {
      fields.addAll([
        _field(
          l10n.profileLeagueLabel,
          user.ligue,
          icon: Icons.emoji_events_outlined,
        ),
      ]);
    } else if (user.isRecruiter) {
      fields.addAll([
        _field(
          user.isAgent
              ? l10n.profileAgencyLabel
              : l10n.profileRecruitmentStructureLabel,
          user.entreprise,
          icon: Icons.business_outlined,
        ),
        _field(
          user.isAgent
              ? l10n.profilePlacementsLabel
              : l10n.profileRecruitmentsLabel,
          user.nombreDeRecrutements?.toString(),
          icon: Icons.how_to_reg_outlined,
          compact: true,
        ),
      ]);
    } else {
      fields.add(_field(l10n.profileNoInfoLabel, l10n.profileNoInfoMessage));
    }

    return _infoTileGrid(fields, l10n);
  }

  String _bioSectionTitle(AppLocalizations l10n, AppUser user) {
    if (user.isPlayer) return l10n.profileBioTitlePlayer;
    if (user.isCoach) return l10n.profileBioTitleCoach;
    if (user.isClub) return l10n.profileBioTitleClub;
    if (user.isRecruiter) {
      return user.isAgent
          ? l10n.profileBioTitleAgent
          : l10n.profileBioTitleRecruiter;
    }
    return l10n.profileBioTitleDefault;
  }

  String _emptyBioMessage(AppLocalizations l10n, AppUser user) {
    if (user.isPlayer) return l10n.profileEmptyBioPlayer;
    if (user.isCoach) return l10n.profileEmptyBioCoach;
    if (user.isClub) return l10n.profileEmptyBioClub;
    if (user.isRecruiter) {
      return user.isAgent
          ? l10n.profileEmptyBioAgent
          : l10n.profileEmptyBioRecruiter;
    }
    return l10n.profileEmptyBioDefault;
  }

  Widget _buildAdvancedFootballSectionClean(
    AppUser user,
    AppLocalizations l10n, {
    required bool isOwnProfile,
  }) {
    if (!user.hasAdvancedProfile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profileAdvancedEmptyTitle,
            style: const TextStyle(color: AdColors.onSurfaceMuted),
          ),
          const SizedBox(height: 8),
          Text(
            user.isPlayer
                ? l10n.profileAdvancedEmptyPlayerHint
                : user.isClub
                ? l10n.profileAdvancedEmptyClubHint
                : user.isRecruiter
                ? user.isAgent
                      ? l10n.profileAdvancedEmptyAgentHint
                      : l10n.profileAdvancedEmptyRecruiterHint
                : l10n.profileAdvancedEmptyDefaultHint,
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
          //
          // Regroupees deux par deux quand leur valeur tient sur une demi-
          // largeur (un mot, un chiffre) : c'est ce qui evite qu'un profil
          // joueur complet empile quinze cartes pleine largeur.
          _infoTileGrid([
            _field(
              l10n.profileStrongFootLabel,
              football.strongFoot?.labelFr,
              icon: Icons.sports_soccer_outlined,
              compact: true,
            ),
            _field(
              l10n.profileHeightLabel,
              countLabel(football.heightCm, 'cm'),
              icon: Icons.height_outlined,
              compact: true,
            ),
            _field(
              l10n.profileWeightLabel,
              countLabel(football.weightKg, 'kg'),
              icon: Icons.monitor_weight_outlined,
              compact: true,
            ),
            _field(
              l10n.profileNationalitiesLabel,
              football.nationalities.isEmpty
                  ? null
                  : football.nationalities.map(countryLabel).join(' · '),
              icon: Icons.public_outlined,
            ),
          ], l10n),
          // L'annee de naissance n'est plus reprise ici : elle est affichee
          // une fois, avec le reste de l'identite, dans la section du dessus.
          const Divider(),
          _infoTileGrid([
            _field(
              l10n.profileLevelFieldLabel,
              football.currentClubLevel?.labelFr,
              icon: Icons.stairs_outlined,
              compact: true,
            ),
            _field(
              l10n.profileStatusLabel,
              football.contractStatus?.labelFr,
              icon: Icons.assignment_outlined,
              compact: true,
            ),
            _field(
              l10n.profileContractEndLabel,
              football.contractStatus?.expectsEndDate == true &&
                      football.contractEndDate != null
                  ? _formatDate(football.contractEndDate!)
                  : null,
              icon: Icons.event_outlined,
              compact: true,
            ),
          ], l10n),
          const Divider(),
          _infoTileGrid([
            _field(
              l10n.profileSeasonLabel,
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
            _field(
              l10n.profileAppearancesLabel,
              season?.appearances?.toString(),
              icon: Icons.numbers_outlined,
              compact: true,
            ),
            _field(
              l10n.profilePlaytimeLabel,
              countLabel(season?.minutes, 'min'),
              icon: Icons.timer_outlined,
              compact: true,
            ),
            _field(
              l10n.profileGoalsLabel,
              season?.goals?.toString(),
              icon: Icons.sports_score_outlined,
              compact: true,
            ),
            _field(
              l10n.profileAssistsLabel,
              season?.assists?.toString(),
              icon: Icons.assistant_direction_outlined,
              compact: true,
            ),
          ], l10n),

          // Le parcours, sous la saison en cours : c'est la lecture d'un
          // recruteur, du present vers ce qui y a mene. Une seule saison ne
          // dit pas si un joueur progresse.
          if (football.seasonHistory.isNotEmpty) ...[
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.profileHistoryTitle,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 6),
            for (final archived in football.seasonHistory)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _infoTile(
                  [?archived.season, ?archived.clubName].join(' · '),
                  _pastSeasonSummary(archived, l10n),
                  l10n,
                  icon: Icons.history_rounded,
                ),
              ),
          ],

          // La provenance, collee aux chiffres et non reléguée dans un badge
          // en haut de page : c'est ici qu'on les lit, donc ici qu'il faut
          // savoir qui les dit.
          _buildStatsProvenance(user, l10n),

          const Divider(),
          _infoTileGrid([
            _field(
              l10n.profileOpenToOpportunitiesLabel,
              user.openToOpportunities == null
                  ? null
                  : (user.openToOpportunities == true
                        ? l10n.profileYesLabel
                        : l10n.profileNoLabel),
              icon: Icons.travel_explore,
              compact: true,
            ),
          ], l10n),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              user.hasScoutReadyProfile
                  ? l10n.profileScoutReadyLabel
                  : l10n.profileScoutPartialLabel,
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
          // Deux blocs, pas un. « Poste » et « Pied fort » etaient presentes
          // au meme rang dans une liste de neuf : le joueur remplissait sa
          // taille, voyait la liste raccourcir, et restait introuvable. Le
          // premier bloc dit ce qui empeche d'exister, le second ce qui
          // peaufine. La separation vient du modele, cet ecran ne soustrait
          // rien lui-meme.
          if (isOwnProfile &&
              (!user.hasScoutReadyProfile || user.isHiddenFromSearchByChoice))
            _MissingScoutRequirements(
              blocking: user.missingSearchRequirements,
              missing: user.missingScoutOnlyRequirements,
              hiddenByChoice: user.isHiddenFromSearchByChoice,
            ),
        ],
      );
    }

    if (user.isClub) {
      final club = user.club;

      return _infoTileGrid([
        _field(
          l10n.profileClubLevelLabel,
          club.level?.labelFr,
          icon: Icons.account_tree_outlined,
          compact: true,
        ),
        _field(
          l10n.profileClubCategoriesLabel,
          club.ageCategories.isEmpty
              ? null
              : club.ageCategories.map((c) => c.labelFr).join(' · '),
          icon: Icons.groups_2_outlined,
        ),
        // Les besoins de recrutement ne sont plus ici : ils vivent dans les
        // offres, qui sont datees, moderees et candidatables. Deux sources
        // pour un seul fait finissent par se contredire.
        _field(
          l10n.profileClubFederationIdLabel,
          club.federationId,
          icon: Icons.badge_outlined,
          compact: true,
        ),
      ], l10n);
    }

    if (user.isRecruiter) {
      final agent = user.agent;

      return _infoTileGrid([
        _field(
          user.isAgent
              ? l10n.profileLicenseNumberLabel
              : l10n.profileAgentLicenseRefLabel,
          agent.licenceNumber,
          icon: Icons.badge_outlined,
          compact: true,
        ),
        _field(
          l10n.profileLicenseCountryLabel,
          agent.licenceCountry == null
              ? null
              : countryLabel(agent.licenceCountry),
          icon: Icons.flag_circle_outlined,
          compact: true,
        ),
        _field(
          user.isAgent
              ? l10n.profileAgentCountriesLabel
              : l10n.profileRecruiterCountriesLabel,
          agent.countries.isEmpty
              ? null
              : agent.countries.map(countryLabel).join(' · '),
          icon: Icons.public_outlined,
        ),
      ], l10n);
    }

    return Text(l10n.profileNoAdvancedProfileMessage);
  }

  Widget _buildEvidenceSectionClean(AppUser user, AppLocalizations l10n) {
    final tiles = <Widget>[];

    if (user.isPlayer) {
      if (user.cvUrl != null) {
        tiles.add(
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: Text(l10n.profileCvViewTitle),
              subtitle: Text(l10n.profileCvViewSubtitle),
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
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(l10n.profileCvMissingTitle),
              subtitle: Text(l10n.profileCvMissingSubtitle),
            ),
          ),
        );
      }
    }

    return Column(children: tiles);
  }

  String _publicSectionTitleClean(AppLocalizations l10n, AppUser user) {
    if (user.isPlayer) return l10n.profilePublicTitlePlayer;
    if (user.isCoach) return l10n.profilePublicTitleCoach;
    if (user.isClub) return l10n.profilePublicTitleClub;
    if (user.isRecruiter) {
      return user.isAgent
          ? l10n.profilePublicTitleAgent
          : l10n.profilePublicTitleRecruiter;
    }
    return l10n.profilePublicTitleDefault;
  }

  String _advancedSectionTitleClean(AppLocalizations l10n, AppUser user) {
    if (user.isPlayer) return l10n.profileAdvancedTitlePlayer;
    if (user.isClub) return l10n.profileAdvancedTitleClub;
    if (user.isRecruiter) {
      return user.isAgent
          ? l10n.profileAdvancedTitleAgent
          : l10n.profileAdvancedTitleRecruiter;
    }
    return l10n.profileAdvancedTitleDefault;
  }

  Widget _buildFollowMessageRow(
    AppUser user,
    AppLocalizations l10n, {
    required bool canMessage,
  }) {
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
            label: isFollowing
                ? l10n.profileUnfollowButton
                : l10n.profileFollowButton,
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

                        AdFeedback.error(
                          l10n.profileActionErrorTitle,
                          l10n.profileActionImpossibleMessage,
                        );
                      }
                    } catch (_) {
                      _profileController.applyLocalFollowerChange(
                        currentUserId: currentUserId,
                        shouldFollow: isFollowing,
                      );
                      AdFeedback.error(
                        l10n.profileActionErrorTitle,
                        l10n.profileActionImpossibleNowMessage,
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
            label: l10n.profileContactButton,
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

  /// Qui repond des chiffres affiches au-dessus.
  ///
  /// L'ecran ne rejuge rien : il recopie [AppUser.statsProvenance], qui derive
  /// de la verification du compte. Refaire ici le test sur `profileVerified`,
  /// c'est se donner deux endroits qui peuvent finir par se contredire -- et
  /// se contredire sur ce point precis reviendrait a afficher une garantie que
  /// personne n'a donnee.
  Widget _buildStatsProvenance(AppUser user, AppLocalizations l10n) {
    final provenance = user.statsProvenance;
    final (IconData icon, Color color, String label) = switch (provenance) {
      StatsProvenance.attested => (
        Icons.verified_rounded,
        AdColors.success,
        user.profileVerifiedAt == null
            ? l10n.profileStatsAttestedMessage
            : l10n.profileStatsAttestedWithDateMessage(
                _formatDate(user.profileVerifiedAt!),
              ),
      ),
      StatsProvenance.suspended => (
        Icons.shield_moon_outlined,
        AdColors.warning,
        l10n.profileStatsSuspendedMessage,
      ),
      // Dit, et non tu. Le taire laisserait un recruteur croire a une
      // garantie que personne n'a donnee -- et c'est cette confusion-la qui
      // decredibilise une base entiere, pas le fait d'etre declaratif.
      StatsProvenance.declared => (
        Icons.info_outline_rounded,
        AdColors.onSurfaceMuted,
        l10n.profileStatsDeclaredMessage,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ce qu'une saison passee a produit, en une ligne.
  ///
  /// Le niveau du club y figure parce qu'il change tout : « 28 matchs, 11
  /// buts » ne pese pas la meme chose en academie et en premiere division.
  String? _pastSeasonSummary(SeasonRecord season, AppLocalizations l10n) {
    final parts = <String>[
      ?season.competition,
      ?season.clubLevel?.labelFr,
      ?season.ageCategory?.code,
      if (season.appearances != null)
        l10n.profileSeasonSummaryAppearances(season.appearances!),
      if (season.minutes != null)
        l10n.profileSeasonSummaryMinutes(season.minutes!),
      if (season.goals != null) l10n.profileSeasonSummaryGoals(season.goals!),
      if (season.assists != null)
        l10n.profileSeasonSummaryAssists(season.assists!),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _infoTile(
    String label,
    String? value,
    AppLocalizations l10n, {
    IconData? icon,
  }) {
    final hasValue = value?.isNotEmpty == true;

    return Container(
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
                  hasValue ? value! : l10n.commonNotSpecified,
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

  /// Un champ pour [_infoTileGrid] : `compact` dit si sa valeur tient toujours
  /// sur une largeur de moitie d'ecran (un chiffre, un mot, une date) plutot
  /// que d'exiger la pleine largeur (une liste de postes, un club, une bio).
  ({String label, String? value, IconData? icon, bool compact}) _field(
    String label,
    String? value, {
    IconData? icon,
    bool compact = false,
  }) => (label: label, value: value, icon: icon, compact: compact);

  /// Deux cartes cote a cote pour les champs `compact` consecutifs, une carte
  /// pleine largeur pour les autres.
  ///
  /// Sans lui, chaque fait de la fiche -- y compris « Taille : 178 cm » ou
  /// « Pied fort : Droit » -- occupait sa propre ligne pleine largeur : un
  /// profil joueur complet empilait plus de quinze cartes, et le recruteur
  /// faisait defiler l'ecran pour lire douze mots. Les champs dont la valeur
  /// peut etre longue (postes, nationalites, club, saison) restent seuls sur
  /// leur ligne ; les autres se groupent par deux des qu'ils se suivent.
  Widget _infoTileGrid(
    List<({String label, String? value, IconData? icon, bool compact})> fields,
    AppLocalizations l10n,
  ) {
    final rows = <Widget>[];
    ({String label, String? value, IconData? icon, bool compact})?
    pendingCompact;

    Widget tileFor(
      ({String label, String? value, IconData? icon, bool compact}) field,
    ) => _infoTile(field.label, field.value, l10n, icon: field.icon);

    void flushPending() {
      final field = pendingCompact;
      if (field == null) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: tileFor(field),
        ),
      );
      pendingCompact = null;
    }

    for (final field in fields) {
      if (!field.compact) {
        flushPending();
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: tileFor(field),
          ),
        );
        continue;
      }

      final previous = pendingCompact;
      if (previous == null) {
        pendingCompact = field;
        continue;
      }

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tileFor(previous)),
              const SizedBox(width: 10),
              Expanded(child: tileFor(field)),
            ],
          ),
        ),
      );
      pendingCompact = null;
    }
    flushPending();

    return Column(children: rows);
  }
}

// =======================
// Widgets secondaires
// =======================
