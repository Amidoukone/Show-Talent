import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/screens/add_video.dart'; // ✅ nouveau fichier à utiliser
import 'package:adfoot/screens/full_screen_video.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VideoController videoController = Get.put(VideoController());
  final UserController userController = Get.find<UserController>();
  final VideoManager _videoManager = VideoManager();
  final PageController _pageController = PageController();

  String? currentVideoUrl;
  bool _isConnected = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
    _listenToConnectionChanges();

    _pageController.addListener(() {
      final maxScroll = _pageController.position.maxScrollExtent;
      final currentScroll = _pageController.position.pixels;

      if (maxScroll - currentScroll <= 300 &&
          !videoController.isLoading &&
          videoController.hasMore) {
        videoController.fetchPaginatedVideos();
      }
    });
  }

  Future<void> _checkInitialConnection() async {
    final resultList = await Connectivity().checkConnectivity();
    setState(() => _isConnected = resultList != ConnectivityResult.none);
    if (_isConnected && videoController.videoList.isEmpty) {
      videoController.fetchPaginatedVideos();
    }
  }

  void _listenToConnectionChanges() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((resultList) {
      final result = resultList.firstOrNull;
      final wasConnected = _isConnected;
      setState(() => _isConnected = result != null && result != ConnectivityResult.none);

      if (!_isConnected) return;

      if (!wasConnected && videoController.videoList.isEmpty) {
        videoController.fetchPaginatedVideos();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
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
                child: CircularProgressIndicator(),
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
              onPressed: () {
                if (currentVideoUrl != null) {
                  _videoManager.pause(currentVideoUrl!);
                }
                Get.to(() => ProfileScreen(uid: user.uid));
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
                onPageChanged: (index) {
                  _handlePageChange(index, videos);
                },
                itemBuilder: (context, index) {
                  final video = videos[index];
                  final effectiveUrl = video.hlsUrl ?? video.videoUrl;

                  return Stack(
                    children: [
                      SmartVideoPlayer(
                        videoUrl: effectiveUrl,
                        video: video,
                        currentIndex: index,
                        videoList: videos,
                        enableTapToPlay: false,
                      ),
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              _videoManager.pause(effectiveUrl);
                              Get.to(() => FullScreenVideo(
                                    video: video,
                                    user: userController.user!,
                                    videoController: videoController,
                                  ));
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: Obx(() {
        if (userController.user?.role == 'joueur') {
          return FloatingActionButton(
            backgroundColor: const Color(0xFF214D4F),
            foregroundColor: Colors.white,
            heroTag: 'addVideo',
            onPressed: () {
              if (currentVideoUrl != null) {
                _videoManager.pause(currentVideoUrl!);
              }
              Get.to(() => const AddVideo()); // ✅ redirection vers nouveau flux
            },
            child: const Icon(Icons.add),
          );
        } else {
          return const SizedBox.shrink();
        }
      }),
    );
  }

  void _handlePageChange(int index, List<dynamic> videos) {
    if (index >= videos.length) return;

    final previousUrl = currentVideoUrl;
    final video = videos[index];
    final effectiveUrl = video.hlsUrl ?? video.videoUrl;

    currentVideoUrl = effectiveUrl;

    if (previousUrl != null && previousUrl != currentVideoUrl) {
      _videoManager.pause(previousUrl);
    }

    _videoManager.play(effectiveUrl);
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
