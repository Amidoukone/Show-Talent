import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/connectivity_controller.dart';
import 'package:adfoot/screens/add_video.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/widgets/smart_video_player.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final VideoController videoController;
  final UserController userController = Get.find<UserController>();
  final PageController _pageController = PageController();

  bool _isConnected = true;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  StreamSubscription<bool>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    const contextKey = 'home';
    videoController = Get.put(
      VideoController(contextKey: contextKey),
      tag: contextKey,
      permanent: true,
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _initConnectivityListener();
    _loadInitialVideos();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    _pageController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      videoController.pauseAll();
    } else if (state == AppLifecycleState.resumed) {
      videoController.currentIndex.refresh();
    }
    super.didChangeAppLifecycleState(state);
  }

  void _initConnectivityListener() {
    _connectivitySubscription = ConnectivityService()
        .connectionStream
        .distinct()
        .listen((connected) async {
      if (!mounted) return;
      setState(() => _isConnected = connected);
      if (connected && videoController.videoList.isEmpty) {
        await videoController.fetchPaginatedVideos();
      }
    });
  }

  Future<void> _loadInitialVideos() async {
    final connected = await ConnectivityService().checkInitialConnection();
    if (!mounted) return;
    setState(() => _isConnected = connected);

    if (connected && videoController.videoList.isEmpty) {
      await videoController.fetchPaginatedVideos();
    }

    if (mounted) _fadeController.forward();
  }

  void _onPageChanged(int index) {
    videoController.currentIndex.value = index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'AD.FOOT',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        actions: [
          Obx(() {
            final user = userController.user;
            if (user == null) {
              return const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            return IconButton(
              icon: CircleAvatar(
                backgroundImage: NetworkImage(
                  user.photoProfil.isNotEmpty
                      ? user.photoProfil
                      : 'https://via.placeholder.com/150',
                ),
              ),
              onPressed: () async {
                await videoController.pauseAll();
                await Get.to(() => ProfileScreen(uid: user.uid, isReadOnly: false));
                videoController.currentIndex.refresh();
              },
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
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final video = videos[index];
                  return Stack(
                    children: [
                      SmartVideoPlayer(
                        key: ValueKey(video.id),
                        contextKey: 'home',
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
                                    shadows: [
                                      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  video.caption.isNotEmpty ? video.caption : 'Pas de légende',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    shadows: [
                                      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
                                    ],
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
                          onTap: () async {
                            await videoController.pauseAll();
                            await Get.to(() => ProfileScreen(uid: video.uid, isReadOnly: true));
                            videoController.currentIndex.refresh();
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
            heroTag: 'addVideo',
            onPressed: () async {
              await videoController.pauseAll();
              final result = await Get.to(() => const AddVideo());
              if (result == true) {
                await videoController.refreshVideosIfNeeded();
              }
              videoController.currentIndex.refresh();
            },
            child: const Icon(Icons.add),
          );
        }
        return const SizedBox.shrink();
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
          Text('Pas de connexion Internet', style: TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
    );
  }
}
