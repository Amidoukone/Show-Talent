import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/widgets/smart_video_player.dart';
import 'package:adfoot/controller/connectivity_controller.dart';

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
  late final String effectiveUrl;
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    effectiveUrl = widget.video.videoUrl;
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    final isOnline = await ConnectivityService().checkInitialConnection();
    setState(() => _isConnected = isOnline);
  }

  @override
  Widget build(BuildContext context) {
    final allVideos = widget.videoController.videoList;
    final index = allVideos.indexWhere((v) => v.id == widget.video.id);

    return Scaffold(
      backgroundColor: Colors.black,
      body: !_isConnected
          ? _buildNoInternet()
          : Stack(
              fit: StackFit.expand,
              children: [
               SmartVideoPlayer(
  videoUrl: effectiveUrl,
  video: widget.video,
  currentIndex: index,
  videoList: widget.videoController.videoList,
  enableTapToPlay: false,
  autoPlay: true,
  showControls: false,
  showProgressBar: true, // 👈 important
),
                _buildBackButton(),
                _buildVideoInfo(),
              ],
            ),
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 10,
      child: GestureDetector(
        onTap: () => Get.back(),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _buildVideoInfo() {
    return Positioned(
      bottom: 40,
      left: 10,
      right: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () async {
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
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.video.caption.isNotEmpty ? widget.video.caption : 'Pas de légende',
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
