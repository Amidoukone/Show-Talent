import 'package:get/get.dart';

class VideoPlaybackManager extends GetxController {
  RxString activeVideoId = ''.obs;

  void setActive(String id) => activeVideoId.value = id;

  bool isActive(String id) => activeVideoId.value == id;
}
