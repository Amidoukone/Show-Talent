import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:adfoot/models/video.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:adfoot/controller/video_controller.dart';

class ProfileVideoScrollView extends StatefulWidget {
  final List<Video> videos;
  final int initialIndex;
  final String uid;
  final String contextKey;

  const ProfileVideoScrollView({
    super.key,
    required this.videos,
    required this.initialIndex,
    required this.uid,
    required this.contextKey,
  });

  @override
  State<ProfileVideoScrollView> createState() => _ProfileVideoScrollViewState();
}

class _ProfileVideoScrollViewState extends State<ProfileVideoScrollView>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late final VideoController _vc;
  final VideoManager _videoManager = VideoManager();

  late int _currentIndex;

  bool _isProcessing = false;
  int _requestToken = 0;
  bool _isDisposed = false;

  bool _isExiting = false;

  static const int _videoSlidingWindowLimit = 25;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    _vc = Get.isRegistered<VideoController>(tag: widget.contextKey)
        ? Get.find<VideoController>(tag: widget.contextKey)
        : Get.put(
            VideoController(contextKey: widget.contextKey),
            tag: widget.contextKey,
            permanent: true,
          );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed && !_isExiting) {
        _handleIndexChange(_currentIndex);
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _requestToken++; // annule toutes les async en cours
    WidgetsBinding.instance.removeObserver(this);

    // Le PageController peut disposer sans souci
    _pageController.dispose();

    // IMPORTANT:
    // On ne force PAS de rebuild VideoPlayer ici (l’arbre est déjà en teardown),
    // on stoppe juste la lecture puis on dispose le contexte.
    unawaited(_videoManager.pauseAll(widget.contextKey));
    unawaited(_videoManager.disposeAllForContext(widget.contextKey));

    if (Get.isRegistered<VideoController>(tag: widget.contextKey)) {
      Get.delete<VideoController>(tag: widget.contextKey);
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || _isExiting) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_videoManager.pauseAll(widget.contextKey));
    }
  }

  Future<void> _safeExit() async {
    if (_isDisposed || _isExiting) return;

    setState(() => _isExiting = true);

    // Annule toute logique async en cours (init/preload/disposeUrls)
    _requestToken++;

    // Couper toute lecture + désactiver tout “actif”
    try {
      _vc.currentIndex.value = -1;
    } catch (_) {}

    await _videoManager.pauseAll(widget.contextKey);

    // Laisse Flutter “retirer” proprement les widgets VideoPlayer de l’arbre
    // avant de pop la route (évite le build plugin pendant la transition).
    await WidgetsBinding.instance.endOfFrame;

    if (!_isDisposed && mounted) {
      Get.back();
    }
  }

  Future<void> _handleIndexChange(int idx) async {
    if (_isDisposed || _isExiting) return;
    if (_isProcessing) return;
    if (idx < 0 || idx >= widget.videos.length) return;

    _isProcessing = true;
    final localToken = ++_requestToken;

    try {
      final urls = widget.videos.map((v) => v.videoUrl).toList();
      final currentUrl = urls[idx];

      _vc.currentIndex.value = idx;

      // Pause d’abord (safe)
      await _videoManager.pauseAll(widget.contextKey);
      if (_isDisposed || _isExiting || localToken != _requestToken) return;

      // Init uniquement si toujours actif
      final player = await _videoManager.initializeController(
        widget.contextKey,
        currentUrl,
        autoPlay: true,
        activeUrl: currentUrl,
      );
      if (_isDisposed || _isExiting || localToken != _requestToken) return;

      _currentIndex = idx;
      if (mounted) setState(() {});

      // Preload voisinage (non bloquant)
      _videoManager.preloadSurrounding(
        widget.contextKey,
        urls,
        idx,
        activeUrl: currentUrl,
      );

      // Fenêtre glissante mémoire (dispose hors fenêtre)
      final retained = List<int>.generate(
        _videoSlidingWindowLimit,
        (i) => idx - (_videoSlidingWindowLimit ~/ 2) + i,
      ).where((i) => i >= 0 && i < urls.length);

      final keepUrls = retained.map((i) => urls[i]).toSet();
      final toDispose = urls.toSet().difference(keepUrls);

      if (toDispose.isNotEmpty) {
        // ⚠️ Important: ne dispose pas si on est en train de sortir
        if (!_isExiting && !_isDisposed && localToken == _requestToken) {
          await _videoManager.disposeUrls(widget.contextKey, toDispose.toList());
        }
      }

      // Play sécurisé
      final ctrl = player.controller;
      if (!ctrl.value.isPlaying) {
        await _videoManager.pauseAllExcept(widget.contextKey, currentUrl);
        await ctrl.play();
      }
    } catch (_) {
      // fail-safe
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _safeExit();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Pendant EXITING : on retire PageView -> plus aucun VideoPlayer build
            if (_isExiting)
              const SizedBox.expand(child: ColoredBox(color: Colors.black))
            else
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: widget.videos.length,
                onPageChanged: _handleIndexChange,
                itemBuilder: (_, idx) {
                  final video = widget.videos[idx];
                  final player = _videoManager.getController(
                    widget.contextKey,
                    video.videoUrl,
                  );

                  return SmartVideoPlayer(
                    key: ValueKey(video.id),
                    contextKey: widget.contextKey,
                    videoUrl: video.videoUrl,
                    video: video,
                    currentIndex: idx,
                    videoList: widget.videos,
                    enableTapToPlay: true,
                    autoPlay: true,
                    showControls: true,
                    showProgressBar: true,
                    player: player,
                  );
                },
              ),

            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 30),
                  onPressed: _isExiting ? null : _safeExit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
