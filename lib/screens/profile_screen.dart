// lib/screens/profile_screen.dart
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/screens/profil_video_scrollview.dart';
import 'package:adfoot/widgets/advanced/agent_advanced_form.dart';
import 'package:adfoot/widgets/advanced/club_advanced_form.dart';
import 'package:adfoot/widgets/advanced/player_advanced_form.dart';
import 'package:adfoot/widgets/advanced/player_stats_availability_form.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/profile_controller.dart';
import 'package:adfoot/controller/auth_controller.dart';
import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/chat_screen.dart';
import 'package:adfoot/screens/edit_profil_screen.dart';
import 'package:adfoot/screens/follow_list_screen.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:url_launcher/url_launcher.dart';

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
  // 🎨 Palette officielle
  static const kPrimary = Color(0xFF214D4F);
  static const kAccent = Color(0xFF00BFA6);
  static const kDanger = Color(0xFFE53935);
  static const kSurface = Color(0xFFF7FAFA);

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
    _profileController = Get.put(ProfileController(), tag: widget.uid);
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
    Get.delete<ProfileController>(tag: widget.uid);
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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = controller.user!;
        final currentUid = _authController.currentUid;
        final isOwnProfile = currentUid != null && currentUid == user.uid;
        final visibleVideos = _getVisibleVideos(controller.videoList);

        return Scaffold(
          backgroundColor: kSurface,
          appBar: AppBar(
            backgroundColor: kPrimary,
            title: Text(
              user.nom.isNotEmpty ? user.nom : 'Profil',
            ),
            centerTitle: true,
            actions: [
              if (isOwnProfile && !widget.isReadOnly)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => Get.to(
                    () => EditProfileScreen(
                      user: user,
                      profileController: _profileController,
                    ),
                  ),
                )
              else if (!isOwnProfile && currentUid != null)
                IconButton(
                  icon: const Icon(Icons.message),
                  onPressed: () => _handleSendMessage(user),
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
                        onChangePhoto: () => _changeProfilePhoto(user.uid),
                        profileController: _profileController,
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _StatsCard(user: user),
                    ),
                  ),

                  if (!isOwnProfile)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: _buildFollowMessageRow(user),
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
                              : 'Aucune biographie disponible.',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),

                  // Badge niveau + CTA avancé
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          _buildProfileLevelBadge(user),
                          const Spacer(),
                          if (user.age != null)
                            Text(
                              '${user.age} ans',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.black.withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _buildAdvancedCtaIfNeeded(
                        user,
                        isOwnProfile: isOwnProfile,
                      ),
                    ),
                  ),

                  // 1) Football Base (MVP / Connect)
                  if (!user.isFan)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _SectionCard(
                          title: 'Football — Base',
                          icon: Icons.sports_soccer_outlined,
                          child: _buildBaseFootballSection(user),
                        ),
                      ),
                    ),

                  // 2) Dossier scout (Avancé)
                  if (user.shouldShowAdvancedSection)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _SectionCard(
                          title: 'Dossier scout — Avancé',
                          icon: Icons.auto_awesome_rounded,
                          child: _buildAdvancedFootballSection(user),
                        ),
                      ),
                    ),

                  // 3) Preuves / Documents
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _SectionCard(
                        title: 'Preuves & documents',
                        icon: Icons.folder_open_rounded,
                        child: _buildEvidenceSection(user),
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

                                if (!Get.isRegistered<VideoController>(
                                  tag: contextKey,
                                )) {
                                  Get.put(
                                    VideoController(contextKey: contextKey),
                                    tag: contextKey,
                                    permanent: true,
                                  );
                                }

                                await _profileController.pauseAll();

                                Get.find<VideoController>(tag: contextKey)
                                    .currentIndex
                                    .value = index;

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

                                if (Get.isRegistered<VideoController>(
                                  tag: contextKey,
                                )) {
                                  Get.delete<VideoController>(
                                    tag: contextKey,
                                  );
                                }
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

  // =======================
  // Actions
  // =======================

  Future<void> _handleSendMessage(AppUser user) async {
    final currentUserId = _authController.currentUid;
    if (currentUserId == null) return;

    final conversationId = await _chatController.createOrGetConversation(
      currentUserId: currentUserId,
      otherUserId: user.uid,
    );

    if (conversationId.isNotEmpty) {
      Get.to(
        () => ChatScreen(
          conversationId: conversationId,
          otherUser: user,
        ),
      );
    }
  }

  Future<void> _changeProfilePhoto(String uid) async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (file != null) {
      await _profileController.updateProfilePhoto(uid, file.path);
    }
  }

  // =======================
  // UI helpers (MVP / Avancé)
  // =======================

  Widget _buildProfileLevelBadge(AppUser user) {
    // Couleurs simples, cohérentes et lisibles
    Color bg;
    Color fg = Colors.white;
    IconData icon;

    switch (user.profileLevelLabel) {
      case 'Profil Élite':
        bg = const Color(0xFF1E3A8A); // bleu profond
        icon = Icons.verified_rounded;
        break;
      case 'Profil Avancé':
        bg = kAccent; // ton accent
        icon = Icons.auto_awesome_rounded;
        break;
      case 'Profil Vérifié':
        bg = const Color(0xFF2E7D32); // vert
        icon = Icons.check_circle_rounded;
        break;
      default:
        bg = const Color(0xFF607D8B); // gris bleuté
        icon = Icons.info_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Text(
            user.profileLevelLabel,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedCtaIfNeeded(AppUser user, {required bool isOwnProfile}) {
    // CTA seulement sur son profil (sinon confusion)
    if (!isOwnProfile) return const SizedBox.shrink();
    if (user.isFan) return const SizedBox.shrink();

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
          const Expanded(
            child: Text(
              'Ajoute tes informations avancées (Dossier scout) pour augmenter tes chances d’être repéré.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            onPressed: () {
              if (user.isPlayer) {
                Get.bottomSheet(
                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        children: [
                          PlayerAdvancedForm(
                            user: user,
                            profileController: _profileController,
                          ),
                          const Divider(height: 32),
                          PlayerStatsAvailabilityForm(
                            user: user,
                            profileController: _profileController,
                          ),
                        ],
                      ),
                    ),
                  ),
                  isScrollControlled: true,
                );
              } else if (user.isClub) {
                Get.bottomSheet(
                  ClubAdvancedForm(
                    user: user,
                    profileController: _profileController,
                  ),
                  isScrollControlled: true,
                );
              } else if (user.isRecruiter) {
                Get.bottomSheet(
                  AgentAdvancedForm(
                    user: user,
                    profileController: _profileController,
                  ),
                  isScrollControlled: true,
                );
              }
            },
            child: Text(
              user.hasAdvancedProfile ? 'Modifier' : 'Compléter',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowMessageRow(AppUser user) {
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
            onPressed: () async {
              final ok = isFollowing
                  ? await _followController.unfollowUser(
                      currentUserId, user.uid)
                  : await _followController.followUser(currentUserId, user.uid);

              if (!ok) {
                Get.snackbar(
                  'Erreur',
                  'Action impossible.',
                  backgroundColor: kDanger,
                  colorText: Colors.white,
                );
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.message_outlined),
            label: const Text('Message'),
            onPressed: () => _handleSendMessage(user),
          ),
        ),
      ],
    );
  }

  // =======================
  // Sections (Base / Avancé / Preuves)
  // =======================

  Widget _buildBaseFootballSection(AppUser user) {
    final tiles = <Widget>[];

    // Commun minimal
    if (user.languages != null && user.languages!.isNotEmpty) {
      tiles.add(
        _infoTile('Langues', user.languages!.join(', ')),
      );
    }

    tiles.add(_infoTile('Téléphone', user.phone));

    if (user.isPlayer || user.isCoach) {
      tiles.addAll([
        _infoTile('Position', user.position),
        _infoTile('Club actuel', user.team),
        _infoTile('Matchs joués', user.nombreDeMatchs?.toString()),
        _infoTile('Buts', user.buts?.toString()),
        _infoTile('Passes décisives', user.assistances?.toString()),
      ]);
    } else if (user.isClub) {
      tiles.addAll([
        _infoTile('Nom du club', user.nomClub),
        _infoTile('Ligue', user.ligue),
      ]);
    } else if (user.isRecruiter) {
      tiles.addAll([
        _infoTile('Entreprise', user.entreprise),
        _infoTile('Recrutements', user.nombreDeRecrutements?.toString()),
      ]);
    } else {
      tiles.add(const ListTile(title: Text('Aucune information de base.')));
    }

    return Column(children: tiles);
  }
Widget _buildAdvancedFootballSection(AppUser user) {
  // Si pas encore rempli, on montre un résumé “vide + conseil”
  if (!user.hasAdvancedProfile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ce profil n’a pas encore de données avancées.',
          style: TextStyle(color: Colors.black.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 8),
        Text(
          user.isPlayer
              ? 'Ajoute taille, poids, pied fort, positions, stats et disponibilité.'
              : user.isClub
                  ? 'Ajoute structure, catégories et besoins.'
                  : user.isRecruiter
                      ? 'Ajoute licence et zones.'
                      : 'Complète les informations avancées.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  // ======================
  // 👤 JOUEUR
  // ======================
  if (user.isPlayer) {
    final p = user.playerProfile ?? {};

    // ---- Physical
    final physical = p['physical'] as Map<String, dynamic>? ?? {};
    final height = physical['heightCm']?.toString();
    final weight = physical['weightKg']?.toString();
    final foot = physical['strongFoot']?.toString();

    // ---- Positions & skills
    final positions = (p['positions'] is List)
        ? (p['positions'] as List).join(', ')
        : null;

    final skills = (p['skills'] is List)
        ? (p['skills'] as List).join(', ')
        : null;

    // ---- Stats
    final stats = p['stats'] as Map<String, dynamic>? ?? {};
    final minutes = stats['minutes']?.toString();

    // ---- Availability
    final availability = p['availability'] as Map<String, dynamic>? ?? {};
    final open = availability.containsKey('open')
        ? (availability['open'] == true ? 'Oui' : 'Non')
        : null;

    final regions = (availability['regions'] is List)
        ? (availability['regions'] as List).join(', ')
        : null;

    return Column(
      children: [
        _infoTile('Taille (cm)', height),
        _infoTile('Poids (kg)', weight),
        _infoTile('Pied fort', foot),
        _infoTile('Positions (avancé)', positions),
        _infoTile('Compétences', skills),
        const Divider(),
        _infoTile('Minutes jouées', minutes),
        const Divider(),
        _infoTile('Disponible', open),
        _infoTile('Régions', regions),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            user.hasScoutReadyProfile
                ? '✅ Dossier scout prêt (Élite)'
                : '🟡 Dossier scout partiel',
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

  // ======================
  // 🏟️ CLUB
  // ======================
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
              return prio.isNotEmpty ? '$pos ($prio)' : pos;
            }
            return e.toString();
          })
          .where((s) => s.trim().isNotEmpty)
          .join(', ');
    }

    return Column(
      children: [
        _infoTile('Structure', structureType),
        _infoTile('Catégories', categories),
        _infoTile('Besoins', needsText),
      ],
    );
  }

  // ======================
  // 🧑‍💼 AGENT / RECRUTEUR
  // ======================
  if (user.isRecruiter) {
    final a = user.agentProfile ?? {};

    final license = a['licenseNumber']?.toString();
    final country = a['licenseCountry']?.toString();
    final zones =
        (a['zones'] is List) ? (a['zones'] as List).join(', ') : null;

    return Column(
      children: [
        _infoTile('Licence', license),
        _infoTile('Pays licence', country),
        _infoTile('Zones', zones),
      ],
    );
  }

  return const Text('Aucun profil avancé pour ce rôle.');
}


  Widget _buildEvidenceSection(AppUser user) {
    final tiles = <Widget>[];
    // CV joueur
    if (user.isPlayer) {
      if (user.cvUrl != null) {
        tiles.add(
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
            title: const Text('Voir le CV'),
            subtitle: const Text('Document PDF'),
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
          subtitle: Text('Aucun CV ajouté'),
        ));
      }

      // Performances (Map<String,double>)
      if (user.performances != null && user.performances!.isNotEmpty) {
        final perf = user.performances!;
        final keys = perf.keys.toList()..sort();
        final preview = keys.take(6).map((k) => '$k: ${perf[k]}').join(' • ');

        tiles.add(
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Performances'),
            subtitle: Text(preview),
          ),
        );
      } else {
        tiles.add(const ListTile(
          leading: Icon(Icons.insights_outlined),
          title: Text('Performances'),
          subtitle: Text('Non renseigné'),
        ));
      }
    }

    // Vidéos publiées (simple indicateur ici)
    if (user.isPlayer) {
      final hasVideos = (user.videosPubliees?.isNotEmpty ?? false);
      tiles.add(
        ListTile(
          leading: const Icon(Icons.video_library_outlined),
          title: const Text('Vidéos'),
          subtitle: Text(
            hasVideos ? 'Vidéos disponibles' : 'Aucune vidéo liée au profil',
          ),
        ),
      );
    }

    return Column(children: tiles);
  }

  Widget _infoTile(String label, String? value) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(value?.isNotEmpty == true ? value! : 'Non spécifié'),
    );
  }
}

// =======================
// Widgets secondaires
// =======================

class _HeaderCard extends StatelessWidget {
  final AppUser user;
  final bool isOwnProfile;
  final bool isReadOnly;
  final VoidCallback onChangePhoto;
  final ProfileController profileController;

  const _HeaderCard({
    required this.user,
    required this.isOwnProfile,
    required this.isReadOnly,
    required this.onChangePhoto,
    required this.profileController,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Profil',
      icon: Icons.person_outline,
      child: Column(
        children: [
          Obx(
            () => CircleAvatar(
              radius: 60,
              backgroundImage: user.photoProfil.isNotEmpty
                  ? NetworkImage(user.photoProfil)
                  : null,
              child: profileController.isLoadingPhoto.value
                  ? const CircularProgressIndicator()
                  : null,
            ),
          ),
          if (isOwnProfile && !isReadOnly)
            TextButton.icon(
              onPressed: onChangePhoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Changer la photo'),
            ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final AppUser user;

  const _StatsCard({required this.user});

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(label),
        ],
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
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
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
