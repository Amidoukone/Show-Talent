import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/widgets/video_manager.dart';
import '../models/video.dart';
import '../models/user.dart';

class FullScreenVideo extends StatefulWidget {
  final Video video;
  final AppUser user;
  final dynamic videoController;

  const FullScreenVideo({
    super.key,
    required this.video,
    required this.user,
    required this.videoController,
  });

  @override
  State<FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<FullScreenVideo> {
  bool _isConnected = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _subscription = Connectivity().onConnectivityChanged.listen((resultList) {
      final result = resultList.firstOrNull;
      setState(() => _isConnected = result != null && result != ConnectivityResult.none);
    });
  }

  Future<void> _checkConnection() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => _isConnected = result != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isConnected
          ? Stack(
              fit: StackFit.expand,
              children: [
                SmartVideoPlayer(
                  videoUrl: widget.video.videoUrl,
                  video: widget.video,
                ),
                _buildBackButton(context),
                _buildVideoInfo(context),
              ],
            )
          : _buildNoInternet(),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 10,
      child: GestureDetector(
        onTap: () {
          VideoManager().pause(widget.video.videoUrl);
          Get.back();
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoInfo(BuildContext context) {
    return Positioned(
      bottom: 40,
      left: 10,
      right: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () async {
              VideoManager().pause(widget.video.videoUrl);
              if (widget.video.uid.isNotEmpty) {
                await Get.to(() => ProfileScreen(uid: widget.video.uid, isReadOnly: true));
              } else {
                Get.snackbar(
                  'Erreur',
                  'Utilisateur introuvable.',
                  backgroundColor: Colors.redAccent,
                  colorText: Colors.white,
                );
              }
            },
            child: Row(
              children: [
                CircleAvatar(
                  backgroundImage: NetworkImage(
                    widget.video.profilePhoto.isNotEmpty
                        ? widget.video.profilePhoto
                        : 'https://via.placeholder.com/150',
                  ),
                  radius: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.video.songName.isNotEmpty
                        ? widget.video.songName
                        : 'Musique inconnue',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.video.caption.isNotEmpty
                ? widget.video.caption
                : 'Pas de légende',
            style: const TextStyle(color: Colors.white, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
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
