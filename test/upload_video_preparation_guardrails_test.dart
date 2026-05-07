import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('upload preparation trims long videos instead of hard failing locally',
      () {
    final controller =
        File('lib/controller/upload_video_controller.dart').readAsStringSync();
    final tools = File('lib/utils/video_tools.dart').readAsStringSync();

    expect(controller, contains('VideoTools.prepareVideoFileForUpload'));
    expect(controller, isNot(contains('La duree depasse 60 secondes.')));
    expect(tools, contains('compressVideo('));
    expect(tools, contains('duration: maxDurationSeconds'));
    expect(tools, contains('PreparedVideoFile'));
  });
}
