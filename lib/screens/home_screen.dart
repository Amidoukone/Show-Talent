import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/connectivity_controller.dart';

import 'package:adfoot/screens/profile_screen.dart';

import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final VideoController videoController;
  final UserController userController = Get.find<UserController>();
  final FollowController followController = Get.find<FollowController>();
  final PageController _pageController = PageController();
  final VideoManager videoManager = VideoManager();

  bool _isConnected = true;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  StreamSubscription<bool>? _connectivitySubscription;
  bool _wakelockOn = false;

  Future<void> _setWakelock(bool enable) async {
    if (_wakelockOn == enable) return;
    _wakelockOn = enable;
    try {
      enable ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (e) {
      debugPrint('⚠️ Wakelock error: $e');
    }
  }

  Future<void> _updateWakelockForCurrent() async {
    final idx = videoController.currentIndex.value;
    if (idx < 0 || idx >= videoController.videoList.length) {
      await _setWakelock(false);
      return;
    }
    final url = videoController.videoList[idx].videoUrl;
    final player = videoManager.getController('home', url);
    final ctrl = player?.controller;
    final shouldKeepAwake = ctrl != null &&
        ctrl.value.isInitialized &&
        ctrl.value.isPlaying &&
        !ctrl.value.isBuffering;
    await _setWakelock(shouldKeepAwake);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    videoController = Get.put(
      VideoController(contextKey: 'home'),
      tag: 'home',
      permanent: true,
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _initConnectivityListener();
    _loadInitialVideos();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    _pageController.dispose();
    _connectivitySubscription?.cancel();
    _setWakelock(false);
    unawaited(videoManager.disposeAllForContext('home'));
    super.dispose();
  }

  @override
  void deactivate() {
    videoManager.pauseAll('home');
    _setWakelock(false);
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      videoManager.pauseAll('home');
      _setWakelock(false);
    } else if (state == AppLifecycleState.resumed) {
      final idx = videoController.currentIndex.value;
      if (idx >= 0 && idx < videoController.videoList.length) {
        unawaited(_onPageChanged(idx));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_updateWakelockForCurrent());
        });
      }
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
        final ok = await videoController.fetchPaginatedVideos();
        if (ok && mounted && videoController.videoList.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            videoController.currentIndex.value = 0;
            unawaited(_onPageChanged(0));
            unawaited(_updateWakelockForCurrent());
          });
        }
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final videos = videoController.videoList;
      if (videos.isNotEmpty) {
        videoController.currentIndex.value = 0;
        await _onPageChanged(0);
        await _updateWakelockForCurrent();
      }
    });
  }

  Future<void> _onPageChanged(int index) async {
    final videos = videoController.videoList;
    if (index < 0 || index >= videos.length) return;

    final currentUrl = videos[index].videoUrl;
    videoController.currentIndex.value = index;

    final urls = videos.map((v) => v.videoUrl).toList();
    videoManager.preloadSurrounding('home', urls, index, activeUrl: currentUrl);

    await videoManager.pauseAllExcept('home', currentUrl);

    CachedVideoPlayerPlus? player =
        videoManager.getController('home', currentUrl);
    final ctrl = player?.controller;

    if (ctrl == null ||
        !ctrl.value.isInitialized ||
        ctrl.value.hasError ||
        !mounted) {
      try {
        player = await videoManager.initializeController(
          'home',
          currentUrl,
          autoPlay: true,
          activeUrl: currentUrl,
        );
      } catch (e) {
        debugPrint('❌ Erreur init contrôleur (onPageChanged): $e');
        return;
      }
    }

    final actualCtrl = player?.controller;
    if (actualCtrl != null &&
        actualCtrl.value.isInitialized &&
        !actualCtrl.value.isPlaying &&
        mounted) {
      try {
        await actualCtrl.play();
      } catch (_) {}
    }

    await _updateWakelockForCurrent();

    if (index >= videos.length - 2 &&
        videoController.hasMore &&
        !videoController.isLoading) {
      unawaited(videoController.fetchPaginatedVideos());
    }

    _disposeFarPlayers(index, urls);
  }

  void _disposeFarPlayers(int index, List<String> urls) {
    const window = 25;
    final videos = videoController.videoList;

    if (videos.length <= window) return;

    final start = (index - window ~/ 2).clamp(0, videos.length);
    final end = (start + window).clamp(0, videos.length);

    final keepUrls = videos.sublist(start, end).map((v) => v.videoUrl).toSet();
    final allUrls = urls.toSet();
    final toDispose = allUrls.difference(keepUrls).toList();

    if (toDispose.isNotEmpty) {
      unawaited(videoManager.disposeUrls('home', toDispose));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'AD.FOOT',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        actions: [
          Obx(() {
            final user = userController.user;
            if (user == null) {
              return const Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: GestureDetector(
                onTap: () async {
                  await videoManager.pauseAll('home');
                  await _setWakelock(false);
                  await Get.to(
                    () => ProfileScreen(uid: user.uid, isReadOnly: false),
                  );
                  videoController.currentIndex.refresh();
                  await _updateWakelockForCurrent();
                },
                child: Hero(
                  tag: 'profileAvatar',
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(
                      user.photoProfil.isNotEmpty
                          ? user.photoProfil
                          : 'https://via.placeholder.com/150',
                    ),
                  ),
                ),
              ),
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
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                );
              }

              return PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: videos.length,
                physics: const ClampingScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final video = videos[index];
                  final player =
                      videoManager.getController('home', video.videoUrl);

                  return Stack(
                    fit: StackFit.expand,
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
                        player: player,
                      ),
                      Positioned(
                        bottom: screenHeight * 0.15,
                        left: 12,
                        right: 80,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.songName.isNotEmpty
                                    ? ' ${video.songName}'
                                    : 'Musique inconnue',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      offset: Offset(1, 1),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                video.caption.isNotEmpty
                                    ? video.caption
                                    : 'Pas de légende',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      offset: Offset(1, 1),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: screenHeight * 0.12,
                        right: 16,
                        child: GestureDetector(
                          onTap: () async {
                            await videoManager.pauseAll('home');
                            await _setWakelock(false);
                            await Get.to(() => ProfileScreen(
                                  uid: video.uid,
                                  isReadOnly: true,
                                ));
                            videoController.currentIndex.refresh();
                            await _updateWakelockForCurrent();
                          },
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                backgroundImage: NetworkImage(
                                  video.profilePhoto.isNotEmpty
                                      ? video.profilePhoto
                                      : 'https://via.placeholder.com/150',
                                ),
                                radius: 28,
                              ),
                              if (userController.user?.uid != video.uid &&
                                  !(userController.user?.followingsList
                                          .contains(video.uid) ??
                                      false))
                                Positioned(
                                  bottom: -6,
                                  child: _FollowToggleButton(video: video),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }),
    );
  }

  Widget _buildNoInternet() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: Colors.white70, size: 60),
          SizedBox(height: 20),
          Text('Pas de connexion Internet',
              style: TextStyle(color: Colors.white70, fontSize: 18)),
        ],
      ),
    );
  }
}

// FollowToggleButton class remains unchanged and included below for completeness
class _FollowToggleButton extends StatefulWidget {
  final dynamic video;
  const _FollowToggleButton({required this.video});

  @override
  State<_FollowToggleButton> createState() => _FollowToggleButtonState();
}

class _FollowToggleButtonState extends State<_FollowToggleButton> {
  bool _isLoading = false;
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();

    final userCtrl = Get.find<UserController>();
    final followCtrl = Get.find<FollowController>();
    final currUser = userCtrl.user;
    final targetUid = widget.video.uid;

    return GestureDetector(
      onTap: () async {
        if (_isLoading || currUser == null || currUser.uid == targetUid) return;

        final already = currUser.followingsList.contains(targetUid);

        setState(() {
          _isLoading = true;
          _hidden = true;
          if (already) {
            currUser.followingsList.remove(targetUid);
            currUser.followings--;
          } else {
            currUser.followingsList.add(targetUid);
            currUser.followings++;
          }
        });

        final ok = already
            ? await followCtrl.unfollowUser(currUser.uid, targetUid)
            : await followCtrl.followUser(currUser.uid, targetUid);

        if (!ok && mounted) {
          setState(() {
            _hidden = false;
            if (already) {
              currUser.followingsList.add(targetUid);
              currUser.followings++;
            } else {
              currUser.followingsList.remove(targetUid);
              currUser.followings--;
            }
            _isLoading = false;
          });
          Get.snackbar('Erreur', 'Impossible d’effectuer l’action.',
              backgroundColor: Colors.red, colorText: Colors.white);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 1, 35, 93),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add, size: 16, color: Colors.white),
      ),
    );
  }
}
