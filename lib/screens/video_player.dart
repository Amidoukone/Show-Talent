import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/screens/video_player_item.dart';

class VideoPlayerScreen extends StatelessWidget {  // Notez que j'ai renommé pour éviter les conflits avec VideoPlayer
  final VideoController _videoController = Get.put(VideoController());

  VideoPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,  // Fond noir pour une meilleure expérience vidéo
      body: Obx(() {
        if (_videoController.videoList.isEmpty) {
          return const Center(child: Text('Aucune vidéo disponible', style: TextStyle(color: Colors.white)));
        }

        // Défilement vertical des vidéos
        return PageView.builder(
          itemCount: _videoController.videoList.length,
          controller: PageController(initialPage: 0, viewportFraction: 1),
          scrollDirection: Axis.vertical,
          itemBuilder: (context, index) {
            final video = _videoController.videoList[index];

            return Stack(
              children: [
                VideoPlayerItem(videoUrl: video.videoUrl),  // Jouer la vidéo
                Positioned(
                  bottom: 40,
                  left: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.songName,
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        video.caption,
                        style: const TextStyle(fontSize: 14, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }
}
