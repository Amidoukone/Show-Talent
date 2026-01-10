import 'dart:async';
import 'dart:ui';

import 'package:adfoot/screens/add_video.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:adfoot/controller/video_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/controller/follow_controller.dart';
import 'package:adfoot/controller/connectivity_controller.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/theme/ad_colors.dart';

import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/videos/domain/video_focus_orchestrator.dart';
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
  late final VideoFocusOrchestrator _focusOrchestrator;

  bool _isConnected = true;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  StreamSubscription<bool>? _connectivitySubscription;
  bool _wakelockOn = false;

  // ---------------------------------------------------------------------------
  // Wakelock helpers
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Focus orchestrator helpers
  // ---------------------------------------------------------------------------

  List<Video> get _currentVideos => videoController.videoList.toList();

  void _refreshFocusVideos() {
    _focusOrchestrator.updateVideos(_currentVideos);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    videoController = Get.put(
      VideoController(contextKey: 'home'),
      tag: 'home',
      permanent: true,
    );

    _focusOrchestrator = VideoFocusOrchestrator(
      contextKey: 'home',
      videoManager: videoManager,
      videos: _currentVideos,
      disposeWindow: 25,
      onRequestMore: () async {
        if (videoController.hasMore && !videoController.isLoading) {
          final fetched = await videoController.fetchPaginatedVideos();
          if (fetched) {
            _refreshFocusVideos();
          }
        }
      },
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
    unawaited(_setWakelock(false));
    unawaited(_focusOrchestrator.onDispose());
    super.dispose();
  }

  @override
  void deactivate() {
    videoManager.pauseAll('home');
    unawaited(_setWakelock(false));
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      videoManager.pauseAll('home');
      unawaited(_setWakelock(false));
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

  // ---------------------------------------------------------------------------
  // Connectivity & initial load
  // ---------------------------------------------------------------------------

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
            _refreshFocusVideos();
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
      _refreshFocusVideos();
    }

    if (mounted) _fadeController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final videos = videoController.videoList;
      if (videos.isNotEmpty) {
        videoController.currentIndex.value = 0;
        _refreshFocusVideos();
        await _onPageChanged(0);
        await _updateWakelockForCurrent();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Page change / playback orchestration
  // ---------------------------------------------------------------------------

  Future<void> _onPageChanged(int index) async {
    final videos = videoController.videoList;
    if (index < 0 || index >= videos.length) return;

    videoController.currentIndex.value = index;

    _refreshFocusVideos();
    await _focusOrchestrator.onIndexChanged(index);

    await Future.delayed(const Duration(milliseconds: 50));
    await _updateWakelockForCurrent();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    // ✅ Ombre ultra légère (TikTok-like) : lisibilité sans masquer la vidéo
    const textShadow = <Shadow>[
      Shadow(
        offset: Offset(0, 1),
        blurRadius: 2,
        color: Color(0x55000000), // très léger
      ),
    ];

    return Scaffold(
      backgroundColor: AdColors.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
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
                  _refreshFocusVideos();
                  await _onPageChanged(videoController.currentIndex.value);
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
                final user = userController.user;
                return Stack(
                  children: [
                    const Center(
                      child: Text(
                        'Aucune vidéo disponible',
                        style: TextStyle(
                          color: AdColors.onSurfaceMuted,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (user != null && user.role == 'joueur')
                      Positioned(
                        bottom: 32,
                        right: 24,
                        child: FloatingActionButton(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          onPressed: () async {
                            await videoManager.pauseAll('home');
                            await _setWakelock(false);
                            final result = await Get.to(() => const AddVideo());
                            if (result == true) {
                              await videoController.refreshVideos();
                            }
                          },
                          child: const Icon(Icons.add),
                        ),
                      ),
                  ],
                );
              }

              return PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: videos.length,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (i) => unawaited(_onPageChanged(i)),
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

                      // ✅ Texte "TikTok-like": sans background, sans gradient masquant la vidéo
                      Positioned(
                        bottom: screenHeight * 0.14,
                        left: 16,
                        right: 96,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.play_circle_fill_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      video.description.trim().isNotEmpty
                                          ? video.description.trim()
                                          : 'Pas de description',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ).copyWith(shadows: textShadow),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                video.caption.trim().isNotEmpty
                                    ? video.caption.trim()
                                    : 'Pas de légende',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.3,
                                ).copyWith(shadows: textShadow),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
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
          CircleAvatar(
            radius: 34,
            backgroundColor: AdColors.surfaceAlt,
            child: Icon(
              Icons.wifi_off_rounded,
              color: AdColors.onSurfaceMuted,
              size: 36,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Pas de connexion Internet',
            style: TextStyle(
              color: AdColors.onSurfaceMuted,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
