import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/connectivity_controller.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/screens/add_video.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/widgets/smart_video_player.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final VideoController videoController;
  final UserController userController = Get.find<UserController>();
  final PageController _pageController = PageController();
  bool _isConnected = true;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    if (!Get.isRegistered<VideoController>()) {
      videoController = Get.put(VideoController(), permanent: true);
    } else {
      videoController = Get.find<VideoController>();
    }

    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _initConnectivityListener();
    _pageController.addListener(_handleScroll);
    _loadInitialVideos();
    _fadeController.forward();
  }

  void _initConnectivityListener() {
    ConnectivityService().connectionStream.listen((connected) {
      setState(() => _isConnected = connected);
      if (connected && videoController.videoList.isEmpty) {
        videoController.fetchPaginatedVideos();
      }
    });
  }

  Future<void> _loadInitialVideos() async {
    final connected = await ConnectivityService().checkInitialConnection();
    setState(() => _isConnected = connected);
    if (connected && videoController.videoList.isEmpty) {
      await videoController.fetchPaginatedVideos();
    }
  }

  void _handleScroll() {
    final maxScroll = _pageController.position.maxScrollExtent;
    final currentScroll = _pageController.position.pixels;
    if (maxScroll - currentScroll <= 300 &&
        !videoController.isLoading &&
        videoController.hasMore) {
      videoController.fetchPaginatedVideos();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('AD.FOOT', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        actions: [
          Obx(() {
            final user = userController.user;
            if (user == null) {
              return const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              );
            }
            return IconButton(
              icon: CircleAvatar(
                backgroundImage: NetworkImage(
                  user.photoProfil.isNotEmpty ? user.photoProfil : 'https://via.placeholder.com/150',
                ),
              ),
              onPressed: () => Get.to(() => ProfileScreen(uid: user.uid)),
            );
          }),
        ],
      ),
      body: !_isConnected
          ? _buildNoInternet()
          : Obx(() {
              final videos = videoController.videoList;
              if (videos.isEmpty) {
                return const Center(
                  child: Text(
                    'Aucune vidéo disponible',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                );
              }

              return PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  final video = videos[index];
                  return Stack(
                    children: [
                      SmartVideoPlayer(
                        key: ValueKey(video.id),
                        videoUrl: video.videoUrl,
                        video: video,
                        currentIndex: index,
                        videoList: videos,
                        enableTapToPlay: true,
                        autoPlay: true,
                        showControls: true,
                        showProgressBar: true,
                      ),
                      Positioned(
                        bottom: 100,
                        left: 10,
                        right: 80,
                        child: SafeArea(
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  video.songName.isNotEmpty ? video.songName : 'Musique inconnue',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2)],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  video.caption.isNotEmpty ? video.caption : 'Pas de légende',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2)],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: GestureDetector(
                          onTap: () {
                            if (video.uid.isNotEmpty) {
                              Get.to(() => ProfileScreen(uid: video.uid, isReadOnly: true));
                            } else {
                              Get.snackbar(
                                'Erreur',
                                'Utilisateur introuvable.',
                                backgroundColor: Colors.redAccent,
                                colorText: Colors.white,
                              );
                            }
                          },
                          child: CircleAvatar(
                            backgroundImage: NetworkImage(
                              video.profilePhoto.isNotEmpty
                                  ? video.profilePhoto
                                  : 'https://via.placeholder.com/150',
                            ),
                            radius: 24,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Obx(() {
        if (userController.user?.role == 'joueur') {
          return FloatingActionButton(
            backgroundColor: Colors.white70,
            foregroundColor: Colors.black,
            elevation: 1,
            heroTag: 'addVideo',
            shape: const CircleBorder(),
            onPressed: () async {
              final result = await Get.to(() => const AddVideo());
              if (result == true) {
                await videoController.refreshVideos();
              }
            },
            child: const Icon(Icons.add),
          );
        } else {
          return const SizedBox.shrink();
        }
      }),
    );
  }

  Widget _buildNoInternet() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 60),
          SizedBox(height: 20),
          Text(
            'Pas de connexion Internet',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
    );
  }
}
