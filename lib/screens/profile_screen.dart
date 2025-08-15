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
  late final ProfileController _profileController;
  final AuthController _authController = Get.find<AuthController>();
  final FollowController _followController = Get.put(FollowController());
  final ChatController _chatController = Get.put(ChatController());
  final ImagePicker _imagePicker = ImagePicker();
  final VideoManager _videoManager = VideoManager();
  final ScrollController _scrollController = ScrollController();

  static const int visibleWindowSize = 25;

  @override
  void initState() {
    super.initState();
    _profileController = Get.put(ProfileController(), tag: widget.uid);
    _profileController.updateUserId(widget.uid);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_profileController.isLoadingVideos &&
          _profileController.hasMoreVideos) {
        _profileController.fetchUserVideos(widget.uid);
      }
    });
  }

  @override
  void dispose() {
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

        return Scaffold(
          appBar: AppBar(
            title: Text(user.nom.isNotEmpty ? user.nom : 'Nom inconnu'),
            centerTitle: true,
            actions: [
              if (isOwnProfile && !widget.isReadOnly)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => Get.to(() => EditProfileScreen(
                      user: user, profileController: _profileController)),
                )
              else if (!isOwnProfile && currentUid != null)
                IconButton(
                  icon: const Icon(Icons.message),
                  onPressed: () => _handleSendMessage(user),
                )
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => controller.refreshProfileVideos(),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildProfilePhotoSection(
                        user, isOwnProfile, widget.isReadOnly),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  SliverToBoxAdapter(child: _buildStatSection(user)),
                  if (!isOwnProfile)
                    SliverToBoxAdapter(child: _buildFollowUnfollowButton(user)),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  SliverToBoxAdapter(child: _buildBioSection(user)),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  SliverToBoxAdapter(child: _buildSpecificInfoSection(user)),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  if (user.role == 'joueur') ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          childAspectRatio: 9 / 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (c, index) {
                            if (index >= visibleVideos.length) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            final vid = visibleVideos[index];
                            return GestureDetector(
                              onTap: () async {
                                final contextKey = 'profile:${widget.uid}';
                                if (!Get.isRegistered<VideoController>(
                                    tag: contextKey)) {
                                  Get.put(
                                      VideoController(contextKey: contextKey),
                                      tag: contextKey,
                                      permanent: true);
                                }
                                await _profileController.pauseAll();
                                Get.find<VideoController>(tag: contextKey)
                                    .currentIndex
                                    .value = index;
                                await Get.to(() => ProfileVideoScrollView(
                                      videos: visibleVideos,
                                      initialIndex: index,
                                      uid: widget.uid,
                                      contextKey: contextKey,
                                    ));
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(vid.thumbnailUrl,
                                        fit: BoxFit.cover),
                                  ),
                                  const Align(
                                    alignment: Alignment.bottomRight,
                                    child: Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.play_circle_fill,
                                          color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
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
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }  Future<void> _handleSendMessage(AppUser user) async {
    final currentUserId = _authController.currentUid;
    if (currentUserId == null || currentUserId.isEmpty) {
      Get.snackbar('Erreur', 'Veuillez vous connecter.',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    try {
      final conversationId = await _chatController.createOrGetConversation(
        currentUserId: currentUserId,
        otherUserId: user.uid,
      );
      if (conversationId.isNotEmpty) {
        Get.to(
            () => ChatScreen(conversationId: conversationId, otherUser: user));
      }
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible d’envoyer un message : $e',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Widget _buildProfilePhotoSection(
      AppUser user, bool isOwnProfile, bool isReadOnly) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Obx(() => CircleAvatar(
                  radius: 60,
                  backgroundImage: _profileController.isLoadingPhoto.value
                      ? null
                      : NetworkImage(user.photoProfil.isNotEmpty
                          ? user.photoProfil
                          : 'https://via.placeholder.com/150'),
                  child: _profileController.isLoadingPhoto.value
                      ? const CircularProgressIndicator()
                      : null,
                )),
            if (isOwnProfile && !isReadOnly)
              Positioned(
                bottom: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  onPressed: () => _changeProfilePhoto(user.uid),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            if (user.photoProfil.isNotEmpty) {
              _showProfilePhoto(user.photoProfil);
            } else {
              Get.snackbar(
                  'Info', 'Cet utilisateur n\'a pas de photo de profil.',
                  backgroundColor: Colors.blue, colorText: Colors.white);
            }
          },
          child: const Text('Voir la photo de profil'),
        ),
      ],
    );
  }

  void _showProfilePhoto(String photoUrl) {
    Get.dialog(
      Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(photoUrl, fit: BoxFit.contain),
            TextButton(onPressed: Get.back, child: const Text('Fermer')),
          ],
        ),
      ),
    );
  }

  Widget _buildStatSection(AppUser user) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
            onTap: () => Get.to(
                () => FollowListScreen(uid: user.uid, listType: 'followers')),
            child: _buildStatItem('Followers', user.followersList.length)),
        const SizedBox(width: 20),
        GestureDetector(
            onTap: () => Get.to(
                () => FollowListScreen(uid: user.uid, listType: 'followings')),
            child: _buildStatItem('Followings', user.followingsList.length)),
      ],
    );
  }

  Widget _buildStatItem(String label, int value) {
    return Column(
      children: [
        Text('$value',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label),
      ],
    );
  }

  Widget _buildFollowUnfollowButton(AppUser user) {
    final String? currentUserId = _authController.currentUid;
    if (currentUserId == null) return const SizedBox.shrink();

    final isFollowing = user.followersList.contains(currentUserId);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ElevatedButton(
        onPressed: () async {
          try {
            if (isFollowing) {
              await _followController.unfollowUser(currentUserId, user.uid);
              user.followersList.remove(currentUserId);
            } else {
              await _followController.followUser(currentUserId, user.uid);
              user.followersList.add(currentUserId);
            }
            _profileController.update();
          } catch (e) {
            Get.snackbar('Erreur',
                'Une erreur s\'est produite lors de l\'opération : $e',
                backgroundColor: Colors.red, colorText: Colors.white);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isFollowing ? Colors.redAccent : Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(isFollowing ? 'Dessuivre' : 'Suivre',
            style: const TextStyle(fontSize: 16, color: Colors.white)),
      ),
    );
  }

  Future<void> _changeProfilePhoto(String uid) async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      await _profileController.updateProfilePhoto(uid, file.path);
    }
  }

  Widget _buildBioSection(AppUser user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Biographie',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
              user.bio?.isNotEmpty == true
                  ? user.bio!
                  : 'Aucune biographie disponible.',
              style: const TextStyle(fontSize: 16, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildSpecificInfoSection(AppUser user) {
  List<Widget> section = [];

  switch (user.role) {
    case 'joueur':
      section = [
        _infoTile('Position', user.position),
        _infoTile('Club actuel', user.team),
        _infoTile('Nombre de matchs', user.nombreDeMatchs?.toString()),
        _infoTile('Buts', user.buts?.toString()),
        _infoTile('Assistances', user.assistances?.toString()),
        if (user.cvUrl != null)
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
            title: const Text('Voir le CV'),
            subtitle: const Text('Appuyez pour ouvrir le fichier'),
            onTap: () async {
              final uri = Uri.parse(user.cvUrl!);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                Get.snackbar('Erreur', 'Impossible d’ouvrir le CV.',
                    backgroundColor: Colors.red, colorText: Colors.white);
              }
            },
          ),
      ];
      break;

    case 'club':
      section = [
        _infoTile('Nom du Club', user.nomClub),
        _infoTile('Ligue', user.ligue),
      ];
      break;

    case 'recruteur':
      section = [
        _infoTile('Entreprise', user.entreprise),
        _infoTile('Nombre de recrutements', user.nombreDeRecrutements?.toString()),
      ];
      break;

    default:
      return const Text("Aucune information spécifique pour ce rôle.");
  }

  return Column(children: section);
} 

Widget _infoTile(String label, String? value) {
  return ListTile(
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    subtitle: Text(value?.isNotEmpty == true ? value! : 'Non spécifié'),
  );
}

}
