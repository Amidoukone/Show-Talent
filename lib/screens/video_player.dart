
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/video_controller.dart';
import 'package:show_talent/screens/video_player_item.dart';

class VideoPlayer extends StatelessWidget {
  final VideoController _videoController = Get.put(VideoController());

VideoPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        return PageView.builder(
          itemCount: _videoController.videoList.length,
          controller: PageController(initialPage: 0, viewportFraction: 1),
          scrollDirection: Axis.vertical,
          itemBuilder: (context, index) {
            final video = _videoController.videoList[index];
            return Stack(
              children: [
                VideoPlayerItem(videoUrl: video.videoUrl),
                Column(
                  children: [
                    const SizedBox(height: 100),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(video.songName,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                  Text(video.caption,
                                      style: const TextStyle(
                                          fontSize: 14, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                          // Ajout du profil, like, etc.
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      }),
    );
  }
}
