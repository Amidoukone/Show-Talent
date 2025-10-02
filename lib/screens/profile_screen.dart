import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/screens/profil_video_scrollview.dart';
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

  const ProfileScreen({super.key, required this.uid, this.isReadOnly = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Palette
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

  static const int visibleWindowSize = 25;
  static const int maxLoadedVideos = 100;

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
        _profileController.videoList.length < maxLoadedVideos) {
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

  List<Video> _getVisibleVideos(List<Video> fullList) {
    if (fullList.length <= visibleWindowSize) {
      return fullList;
    }
    return fullList.sublist(fullList.length - visibleWindowSize);
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

        // Thème local pour ce profil
        final theme = Theme.of(context).copyWith(
          scaffoldBackgroundColor: kSurface,
          appBarTheme: const AppBarTheme(
            backgroundColor: kPrimary,
            elevation: 1,
            centerTitle: true,
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            iconTheme: IconThemeData(color: Colors.white),
            actionsIconTheme: IconThemeData(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
            ),
          ),
        );

        return Theme(
          data: theme,
          child: Scaffold(
            appBar: AppBar(
              title: Text(user.nom.isNotEmpty ? user.nom : 'Nom inconnu'),
              actions: [
                if (isOwnProfile && !widget.isReadOnly)
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: () => Get.to(
                      () => EditProfileScreen(
                        user: user,
                        profileController: _profileController,
                      ),
                    ),
                  )
                else if (!isOwnProfile && currentUid != null)
                  IconButton(
                    icon: const Icon(Icons.message, color: Colors.white),
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
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _SectionCard(
                          title: 'Informations',
                          icon: Icons.info_outline,
                          child: _buildSpecificInfoSection(user),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    if (user.role == 'joueur') ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Row(
                            children: const [
                              _SectionHeader(
                                icon: Icons.video_collection_outlined,
                                title: 'Vidéos',
                              ),
                            ],
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
                            (c, index) {
                              if (index >= visibleVideos.length) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              final vid = visibleVideos[index];
                              return RepaintBoundary(
                                key: ValueKey(vid.id),
                                child: _VideoTile(
                                  video: vid,
                                  onTap: () async {
                                    final contextKey = 'profile:${widget.uid}';
                                    if (!Get.isRegistered<VideoController>(
                                        tag: contextKey)) {
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
                                        tag: contextKey)) {
                                      Get.delete<VideoController>(
                                          tag: contextKey);
                                    }
                                  },
                                ),
                              );
                            },
                            childCount: visibleVideos.length,
                          ),
                        ),
                      ),
                      if (controller.isLoadingVideos &&
                          controller.hasMoreVideos)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Actions ---

  Future<void> _handleSendMessage(AppUser user) async {
    final currentUserId = _authController.currentUid;
    if (currentUserId == null || currentUserId.isEmpty) {
      Get.snackbar('Erreur', 'Veuillez vous connecter.',
          backgroundColor: kDanger, colorText: Colors.white);
      return;
    }
    try {
      final conversationId = await _chatController.createOrGetConversation(
        currentUserId: currentUserId,
        otherUserId: user.uid,
      );
      if (conversationId.isNotEmpty) {
        Get.to(() => ChatScreen(conversationId: conversationId, otherUser: user));
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible d’envoyer un message : $e',
          backgroundColor: kDanger, colorText: Colors.white);
    }
  }

  Future<void> _changeProfilePhoto(String uid) async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      await _profileController.updateProfilePhoto(uid, file.path);
    }
  }

  Widget _buildFollowMessageRow(AppUser user) {
    final String? currentUserId = _authController.currentUid;
    if (currentUserId == null) return const SizedBox.shrink();

    // on vérifie si l’utilisateur courant figure dans la liste des abonnés du profil
    final bool isFollowing = user.followersList.contains(currentUserId);

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              // Mise à jour locale optimiste
              if (isFollowing) {
                user.followersList.remove(currentUserId);
              } else {
                user.followersList.add(currentUserId);
              }
              _profileController.update();

              final bool ok = isFollowing
                  ? await _followController.unfollowUser(currentUserId, user.uid)
                  : await _followController.followUser(currentUserId, user.uid);

              if (!ok) {
                // rollback
                if (isFollowing) {
                  user.followersList.add(currentUserId);
                } else {
                  user.followersList.remove(currentUserId);
                }
                _profileController.update();

                Get.snackbar('Erreur', 'Action impossible.',
                    backgroundColor: kDanger, colorText: Colors.white);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isFollowing ? kDanger : kAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(isFollowing ? Icons.person_remove_alt_1 : Icons.person_add_alt),
            label: Text(
              isFollowing ? 'Se désabonner' : 'S’abonner',
              style: const TextStyle(fontSize: 15, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _handleSendMessage(user),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.message_outlined),
            label: const Text('Message',
                style: TextStyle(fontSize: 15, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildSpecificInfoSection(AppUser user) {
    final List<Widget> tiles;

    switch (user.role) {
      case 'joueur':
        tiles = [
          _infoTile('Position', user.position),
          _infoTile('Club actuel', user.team),
          _infoTile('Nombre de matchs', user.nombreDeMatchs?.toString()),
          _infoTile('Buts', user.buts?.toString()),
          _infoTile('Assistances', user.assistances?.toString()),
          if (user.cvUrl != null)
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Voir le CV',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Appuyez pour ouvrir le fichier'),
              onTap: () async {
                final uri = Uri.parse(user.cvUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  Get.snackbar('Erreur', 'Impossible d’ouvrir le CV.',
                      backgroundColor: kDanger, colorText: Colors.white);
                }
              },
            ),
        ];
        break;
      case 'club':
        tiles = [
          _infoTile('Nom du Club', user.nomClub),
          _infoTile('Ligue', user.ligue),
        ];
        break;
      case 'recruteur':
        tiles = [
          _infoTile('Entreprise', user.entreprise),
          _infoTile(
              'Nombre de recrutements', user.nombreDeRecrutements?.toString()),
        ];
        break;
      default:
        tiles = const [
          ListTile(
            title: Text("Aucune information spécifique pour ce rôle."),
          )
        ];
    }

    return Column(children: tiles);
  }

  Widget _infoTile(String label, String? value) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(value?.isNotEmpty == true ? value! : 'Non spécifié'),
      tileColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }
}

// === sous‐widgets ===

class _HeaderCard extends StatelessWidget {
  final AppUser user;
  final bool isOwnProfile;
  final bool isReadOnly;
  final VoidCallback onChangePhoto;
  final ProfileController profileController;

  static const kPrimary = _ProfileScreenState.kPrimary;
  static const kAccent = _ProfileScreenState.kAccent;

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
          Stack(
            alignment: Alignment.center,
            children: [
              Obx(
                () => CircleAvatar(
                  radius: 60,
                  backgroundColor: kPrimary.withOpacity(0.08),
                  backgroundImage: profileController.isLoadingPhoto.value
                      ? null
                      : NetworkImage(
                          user.photoProfil.isNotEmpty
                              ? '${user.photoProfil}?v=${DateTime.now().millisecondsSinceEpoch}'
                              : 'https://via.placeholder.com/150',
                        ),
                  child: profileController.isLoadingPhoto.value
                      ? const CircularProgressIndicator()
                      : null,
                ),
              ),
              if (isOwnProfile && !isReadOnly)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 1,
                    ),
                    onPressed: onChangePhoto,
                    icon: const Icon(Icons.camera_alt_rounded, size: 18),
                    label: const Text('Changer', style: TextStyle(color: Colors.white)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (user.photoProfil.isNotEmpty) {
                      _showProfilePhoto(user.photoProfil);
                    } else {
                      Get.snackbar('Info', 'Cet utilisateur n\'a pas de photo de profil.',
                          backgroundColor: Colors.blue, colorText: Colors.white);
                    }
                  },
                  icon: const Icon(Icons.image_search_rounded),
                  label: const Text('Voir la photo', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showProfilePhoto(String photoUrl) {
    Get.dialog(
      Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              '$photoUrl?v=${DateTime.now().millisecondsSinceEpoch}',
              fit: BoxFit.contain,
            ),
            TextButton(
              onPressed: Get.back,
              child: const Text('Fermer', style: TextStyle(color: Colors.black87)),
            ),
          ],
        ),
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
      title: 'Statistiques',
      icon: Icons.insights_outlined,
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

  static const kPrimary = _ProfileScreenState.kPrimary;

  const _StatChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDFE8E8)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: kPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;

  const _VideoTile({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              video.thumbnailUrl,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            const Positioned(
              right: 6,
              bottom: 6,
              child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 24),
            ),
          ],
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
      elevation: 0.8,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _ProfileScreenState.kPrimary.withOpacity(0.08),
                  child: Icon(icon, color: _ProfileScreenState.kPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: _ProfileScreenState.kPrimary.withOpacity(0.08),
          child: Icon(
            icon,
            color: _ProfileScreenState.kPrimary,
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
