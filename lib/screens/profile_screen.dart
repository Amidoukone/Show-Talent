// lib/screens/profile_screen.dart
import 'package:adfoot/config/feature_controller_registry.dart';
import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/screens/profil_video_scrollview.dart';
import 'package:adfoot/widgets/contact_intake_sheet.dart';
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
import 'package:adfoot/screens/follow_list_screen.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:adfoot/theme/ad_colors.dart';

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
    case 'Profil Elite':
    case 'Profil Élite':
      return const _ProfileLevelStyle(
        backgroundColor: Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        borderColor: Color(0xFF1E3A8A),
        icon: Icons.verified_rounded,
      );
    case 'Profil avancé':
      return const _ProfileLevelStyle(
        backgroundColor: AdColors.accent,
        foregroundColor: Colors.white,
        borderColor: AdColors.accent,
        icon: Icons.auto_awesome_rounded,
      );
    case 'Profil vérifié':
      return const _ProfileLevelStyle(
        backgroundColor: Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        borderColor: Color(0xFF2E7D32),
        icon: Icons.check_circle_rounded,
      );
    default:
      return const _ProfileLevelStyle(
        backgroundColor: Color(0xFFE2E8F0),
        foregroundColor: Color(0xFF334155),
        borderColor: Color(0xFFCBD5E1),
        icon: Icons.info_rounded,
      );
  }
}

class ProfileScreen extends StatefulWidget {
  final String uid;
  final bool isReadOnly;

  const ProfileScreen({
    super.key,
    required this.uid,
    this.isReadOnly = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Palette officielle
  static const kPrimary = AdColors.brand;
  static const kAccent = AdColors.accent;
  static const kDanger = AdColors.error;
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
    _profileController =
        FeatureControllerRegistry.ensureProfileController(widget.uid);
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

    final nearBottom = _scrollController.position.pixels >=
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
    return full.sublist(full.length - _visibleWindowSize);
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
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            centerTitle: true,
            elevation: 0,
            title: Text(
              user.nom.isNotEmpty ? user.nom : 'Profil',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            actions: [
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
                            horizontal: 16, vertical: 12),
                        child: _buildFollowMessageRow(
                          user,
                          canMessage: canMessage,
                        ),
                      ),
                    ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _SectionCard(
                        title: 'Biographie',
                        icon: Icons.notes_rounded,
                        child: Text(
                          user.bio?.isNotEmpty == true
                              ? user.bio!
                              : 'Aucune biographie renseignée.',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),

                  // Badge niveau + CTA avance
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          _buildProfileLevelBadge(user),
                        ],
                      ),
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
                        child: _SectionCard(
                          title: _publicSectionTitleClean(user),
                          icon: Icons.sports_soccer_outlined,
                          child: _buildBaseFootballSectionClean(user),
                        ),
                      ),
                    ),

                  // 2) Informations avancees
                  if (user.shouldShowAdvancedSection)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _SectionCard(
                          title: _advancedSectionTitleClean(user),
                          icon: Icons.auto_awesome_rounded,
                          child: _buildAdvancedFootballSectionClean(user),
                        ),
                      ),
                    ),

                  // 3) Documents et preuves
                  if (_shouldShowEvidenceSection(user))
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _SectionCard(
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
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= visibleVideos.length) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final video = visibleVideos[index];

                            return _VideoTile(
                              video: video,
                              onTap: () async {
                                final contextKey = 'profile:${widget.uid}';
                                final videoController =
                                    FeatureControllerRegistry
                                        .ensureVideoController(
                                  contextKey: contextKey,
                                  enableLiveStream: false,
                                  enableFeedFetch: false,
                                  permanent: true,
                                );

                                await _profileController.pauseAll();

                                videoController.replaceVideos(
                                  visibleVideos,
                                  selectedIndex: index,
                                );

                                await Get.to(
                                  () => ProfileVideoScrollView(
                                    videos: visibleVideos,
                                    initialIndex: index,
                                    uid: widget.uid,
                                    contextKey: contextKey,
                                  ),
                                );

                                await _videoManager
                                    .disposeAllForContext(contextKey);

                                FeatureControllerRegistry
                                    .releaseVideoController(
                                  contextKey,
                                );
                              },
                            );
                          },
                          childCount: visibleVideos.length,
                        ),
                      ),
                    ),
                    if (controller.isLoadingVideos && controller.hasMoreVideos)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
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
    final errorMessage = controller.profileLoadErrorMessage;
    if (errorMessage == null || errorMessage.trim().isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        centerTitle: true,
        elevation: 0,
        title: const Text('Profil'),
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
                  controller.profileLoadErrorTitle ?? 'Profil indisponible',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
      message = 'Vous avez désactivé l\'envoi de messages.';
    } else {
      message = 'Cet utilisateur a désactivé les messages.';
    }

    AdFeedback.warning(
      'Messages indisponibles',
      message,
    );
  }

  Future<void> _handleSendMessage(AppUser user) async {
    if (_isMessageActionLoading) {
      return;
    }

    final currentUser = Get.find<UserController>().user ?? _authController.user;
    final currentUserId = currentUser?.uid ?? _authController.currentUid;
    if (currentUser == null || currentUserId == null) {
      AdFeedback.error(
        'Session invalide',
        'Utilisateur non connecte.',
      );
      return;
    }

    if (!_canSendMessage(user)) {
      _showMessagingDisabledNotice(user);
      return;
    }

    setState(() => _isMessageActionLoading = true);
    try {
      final existingConversationId =
          await _chatController.findExistingConversationId(
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
          'Contact enregistre',
          'Le premier contact a ete cadre et transmis via Adfoot.',
        );
      }

      if (conversationId.isEmpty) {
        AdFeedback.error(
          'Erreur',
          'Impossible d\'ouvrir la messagerie pour le moment.',
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
        'Impossible d\'ouvrir la messagerie pour le moment.',
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
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        centerTitle: true,
        elevation: 0,
        title: Text(
          user.nom.isNotEmpty ? user.nom : 'Profil',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
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
                "Ce profil n'est pas visible pour le moment.",
                style: TextStyle(color: AdColors.onSurfaceMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (canMessage)
                ElevatedButton.icon(
                  onPressed: _isMessageActionLoading
                      ? null
                      : () => _handleSendMessage(user),
                  icon: const Icon(Icons.message_outlined),
                  label: const Text('Contacter'),
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
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
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
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
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
        borderRadius: BorderRadius.circular(999),
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

    final message = user.isPlayer
        ? 'Complétez votre fiche joueur et votre dossier scout pour présenter un profil plus crédible aux clubs et recruteurs.'
        : user.isClub
            ? 'Complétez la présentation de votre club pour afficher clairement votre structure, vos catégories et vos besoins.'
            : user.isRecruiter
                ? user.isAgent
                    ? 'Complétez votre cadre de représentation pour présenter votre agence, votre licence et vos zones d’intervention.'
                    : 'Complétez vos références professionnelles pour présenter votre structure, vos licences et vos zones d’intervention.'
                : 'Complétez les informations avancées du profil.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: kPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            onPressed: () async {
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
            },
            child: Text(user.hasAdvancedProfile ? 'Modifier' : 'Compléter'),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkStatsCard(AppUser user) {
    return _SectionCard(
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

  Widget _buildBaseFootballSectionClean(AppUser user) {
    final tiles = <Widget>[];
    final location = [
      user.city,
      user.region,
      user.country,
    ].where((value) => value?.trim().isNotEmpty == true).join(', ');

    tiles.add(
      _infoTile('Téléphone', user.phone, icon: Icons.phone_outlined),
    );

    if (user.languages != null && user.languages!.isNotEmpty) {
      tiles.add(
        _infoTile('Langues parlées', user.languages!.join(', '),
            icon: Icons.language_outlined),
      );
    }

    if (location.isNotEmpty) {
      tiles.add(
        _infoTile('Localisation', location, icon: Icons.place_outlined),
      );
    }

    if (user.isPlayer || user.isCoach) {
      final teamLabel =
          user.team?.isNotEmpty == true ? user.team : user.clubActuel;
      tiles.addAll([
        _infoTile('Âge', user.age == null ? null : '${user.age} ans',
            icon: Icons.cake_outlined),
        _infoTile(
          user.isCoach ? 'Fonction sportive' : 'Poste principal',
          user.position,
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
        _infoTile('Ligue / championnat', user.ligue,
            icon: Icons.emoji_events_outlined),
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
      tiles.add(
        _infoTile('Informations', 'Aucune information renseignée.'),
      );
    }

    return Column(children: tiles);
  }

  Widget _buildAdvancedFootballSectionClean(AppUser user) {
    if (!user.hasAdvancedProfile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aucune information avancée n\'a encore été renseignée.',
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
      final p = user.playerProfile ?? {};
      final physical = p['physical'] as Map<String, dynamic>? ?? {};
      final height = physical['heightCm']?.toString();
      final weight = physical['weightKg']?.toString();
      final foot = _strongFootLabel(physical['strongFoot']?.toString());
      final positions =
          (p['positions'] is List) ? (p['positions'] as List).join(', ') : null;
      final skills =
          (p['skills'] is List) ? (p['skills'] as List).join(', ') : null;
      final stats = p['stats'] as Map<String, dynamic>? ?? {};
      final minutes = stats['minutes']?.toString();
      final goals = stats['goals']?.toString();
      final assists = stats['assists']?.toString();
      final availability = p['availability'] as Map<String, dynamic>? ?? {};
      final open = availability.containsKey('open')
          ? (availability['open'] == true ? 'Oui' : 'Non')
          : null;
      final regions = (availability['regions'] is List)
          ? (availability['regions'] as List).join(', ')
          : null;

      return Column(
        children: [
          _infoTile(
            'Taille',
            height == null ? null : '$height cm',
            icon: Icons.height_outlined,
          ),
          _infoTile(
            'Poids',
            weight == null ? null : '$weight kg',
            icon: Icons.monitor_weight_outlined,
          ),
          _infoTile('Pied préféré', foot, icon: Icons.sports_soccer_outlined),
          _infoTile('Postes maîtrisés', positions,
              icon: Icons.grid_view_rounded),
          _infoTile('Qualités clés', skills, icon: Icons.star_outline_rounded),
          const Divider(),
          _infoTile(
            'Temps de jeu cumulé',
            minutes == null ? null : '$minutes min',
            icon: Icons.timer_outlined,
          ),
          _infoTile('Buts inscrits', goals, icon: Icons.sports_score_outlined),
          _infoTile('Passes décisives', assists,
              icon: Icons.assistant_direction_outlined),
          const Divider(),
          _infoTile('Ouvert aux opportunités', open,
              icon: Icons.public_outlined),
          _infoTile('Zones ciblées', regions, icon: Icons.travel_explore),
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
                    ? const Color(0xFF2E7D32)
                    : Colors.orange,
              ),
            ),
          ),
        ],
      );
    }

    if (user.isClub) {
      final c = user.clubProfile ?? {};
      final structureType = c['structureType']?.toString();
      final categories = (c['categories'] is List)
          ? (c['categories'] as List).join(', ')
          : null;

      String? needsText;
      final needs = c['needs'];
      if (needs is List && needs.isNotEmpty) {
        needsText = needs
            .map((e) {
              if (e is Map) {
                final pos = e['position']?.toString() ?? '';
                final prio = e['priority']?.toString() ?? '';
                return prio.isNotEmpty
                    ? '$pos (${_priorityLabelClean(prio)})'
                    : pos;
              }
              return e.toString();
            })
            .where((s) => s.trim().isNotEmpty)
            .join(', ');
      }

      return Column(
        children: [
          _infoTile('Type de structure', structureType,
              icon: Icons.account_tree_outlined),
          _infoTile('Catégories encadrées', categories,
              icon: Icons.groups_2_outlined),
          _infoTile('Besoins de recrutement prioritaires', needsText,
              icon: Icons.manage_search_outlined),
        ],
      );
    }

    if (user.isRecruiter) {
      final a = user.agentProfile ?? {};
      final license = a['licenseNumber']?.toString();
      final country = a['licenseCountry']?.toString();
      final zones =
          (a['zones'] is List) ? (a['zones'] as List).join(', ') : null;

      return Column(
        children: [
          _infoTile(
            user.isAgent ? 'Numéro de licence' : 'Référence de licence ou d’agrément',
            license,
            icon: Icons.badge_outlined,
          ),
          _infoTile(
            user.isAgent ? 'Pays de délivrance de la licence' : 'Pays de délivrance',
            country,
              icon: Icons.flag_circle_outlined),
          _infoTile(
            user.isAgent ? 'Zones de représentation' : 'Zones d’intervention',
            zones,
              icon: Icons.public_outlined),
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
          ListTile(
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
        );
      } else {
        tiles.add(const ListTile(
          leading: Icon(Icons.picture_as_pdf_outlined),
          title: Text('CV'),
          subtitle: Text('Aucun CV renseigné'),
        ));
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

  String _priorityLabelClean(String value) {
    switch (value.trim().toLowerCase()) {
      case 'high':
      case 'haute':
        return 'haute priorité';
      case 'medium':
      case 'moyenne':
        return 'priorité moyenne';
      case 'low':
      case 'basse':
        return 'priorité basse';
      default:
        return value;
    }
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
          child: ElevatedButton.icon(
            icon: Icon(
              isFollowing ? Icons.person_remove_alt_1 : Icons.person_add_alt,
            ),
            label: Text(
              isFollowing ? 'Se désabonner' : 'S’abonner',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isFollowing ? kDanger : kAccent,
            ),
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
                              currentUserId, user.uid)
                          : await _followController.followUser(
                              currentUserId, user.uid);

                      if (!ok) {
                        _profileController.applyLocalFollowerChange(
                          currentUserId: currentUserId,
                          shouldFollow: isFollowing,
                        );

                        if (_authController.currentUid == null) {
                          return;
                        }

                        AdFeedback.error(
                          'Erreur',
                          'Action impossible.',
                        );
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
          child: ElevatedButton.icon(
            icon: const Icon(Icons.message_outlined),
            label: const Text('Contacter'),
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

  Widget _infoTile(String label, String? value, {IconData? icon}) {
    final hasValue = value?.isNotEmpty == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AdColors.surfaceCardAlt,
        borderRadius: BorderRadius.circular(12),
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
                    color:
                        hasValue ? AdColors.onSurface : AdColors.onSurfaceMuted,
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

  String _strongFootLabel(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'right':
        return 'Droit';
      case 'left':
        return 'Gauche';
      case 'both':
        return 'Ambidextre';
      default:
        return value ?? '';
    }
  }
}

// =======================
// Widgets secondaires
// =======================

class _HeaderCard extends StatelessWidget {
  final AppUser user;
  final bool isOwnProfile;
  final bool isReadOnly;
  final VoidCallback onViewPhoto;
  final VoidCallback onChangePhoto;
  final ProfileController profileController;

  const _HeaderCard({
    required this.user,
    required this.isOwnProfile,
    required this.isReadOnly,
    required this.onViewPhoto,
    required this.onChangePhoto,
    required this.profileController,
  });

  @override
  Widget build(BuildContext context) {
    final location = user.city ?? user.region ?? user.country;
    final teamLabel =
        user.team?.isNotEmpty == true ? user.team : user.clubActuel;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                AdColors.surfaceCardAlt,
                AdColors.surfaceCard,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AdColors.divider),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 12,
                offset: Offset(0, 6),
              )
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(
                () => GestureDetector(
                  onTap: user.photoProfil.isNotEmpty ? onViewPhoto : null,
                  child: Hero(
                    tag: 'profile-photo-${user.uid}',
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: AdColors.surfaceCard,
                      backgroundImage: user.photoProfil.isNotEmpty
                          ? NetworkImage(user.photoProfil)
                          : null,
                      child: profileController.isLoadingPhoto.value
                          ? const CircularProgressIndicator()
                          : (user.photoProfil.isEmpty
                              ? const Icon(Icons.person, size: 32)
                              : null),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _profileRoleLabel(user).toUpperCase(),
                      style: const TextStyle(
                        color: AdColors.onSurfaceMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoPill(
                          icon: Icons.military_tech_outlined,
                          label: user.profileLevelLabel,
                          style: _profileLevelStyle(user.profileLevelLabel),
                        ),
                        if (user.age != null)
                          _InfoPill(
                            icon: Icons.cake_outlined,
                            label: '${user.age} ans',
                          ),
                        if (teamLabel?.isNotEmpty == true)
                          _InfoPill(
                            icon: Icons.flag_outlined,
                            label: teamLabel!,
                          ),
                        if (location?.isNotEmpty == true)
                          _InfoPill(
                            icon: Icons.place_outlined,
                            label: location!,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bouton photo positionne proprement, sans overflow
        if (isOwnProfile && !isReadOnly)
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              tooltip: 'Changer la photo',
              icon: const Icon(Icons.camera_alt_outlined),
              color: AdColors.brand,
              onPressed: onChangePhoto,
            ),
          ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onTap;

  const _StatChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AdColors.surfaceCardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdColors.divider),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: AdColors.onSurfaceMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;

  const _VideoTile({
    required this.video,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          video.thumbnailUrl,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AdColors.brand),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final _ProfileLevelStyle? style;

  const _InfoPill({
    required this.label,
    required this.icon,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: resolvedStyle?.backgroundColor ?? AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: resolvedStyle?.borderColor ?? AdColors.divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            resolvedStyle?.icon ?? icon,
            size: 18,
            color: resolvedStyle?.foregroundColor ?? AdColors.brand,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: resolvedStyle?.foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
