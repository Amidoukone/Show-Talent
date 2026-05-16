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

  test('upload form ensures its controller before use', () {
    final form = File('lib/screens/upload_form.dart').readAsStringSync();

    expect(form,
        contains('FeatureControllerRegistry.ensureUploadVideoController()'));
    expect(form, isNot(contains('Get.find<UploadVideoController>()')));
  });

  test('upload form releases the preview player before heavy upload work', () {
    final form = File('lib/screens/upload_form.dart').readAsStringSync();

    expect(form, contains('VideoPlayerController? _videoPlayerController;'));
    expect(form, contains('Future<void> _releasePreviewController'));
    expect(form, contains('await _releasePreviewController();'));
    expect(form, contains('identical(_videoPlayerController, controller)'));
  });

  test('upload preparation cancellation invalidates stale async work', () {
    final controller =
        File('lib/controller/upload_video_controller.dart').readAsStringSync();

    expect(controller, contains('int _operationSerial = 0;'));
    expect(controller, contains('final operation = ++_operationSerial;'));
    expect(controller, contains('_isCurrentOperation(operation)'));
    expect(controller, contains('_operationSerial++;'));
    expect(
        controller,
        contains(
            'static const Duration _optimizationOverallTimeout = Duration(seconds: 45);'));
    expect(controller, contains('await _releaseVideoProcessingResources();'));
  });

  test('upload functions normalize paths and validate uploaded objects', () {
    final functions =
        File('functions/src/upload_session.ts').readAsStringSync();

    expect(functions,
        contains('normalizeVideoStoragePath(sessionId, doc?.storagePath)'));
    expect(
        functions,
        contains(
            'normalizeThumbnailStoragePath(sessionId, doc?.thumbnailPath)'));
    expect(functions, contains('resolveUploadLifecycleState(doc)'));
    expect(functions, contains('normalized.startsWith("thumbnails/")'));
    expect(functions,
        contains('await validateVideoUpload(persistedStoragePath);'));
    expect(
      functions,
      contains(
          'await validateThumbnail(persistedThumbnailPath, persistedThumbnailGuard);'),
    );
  });

  test('storage rules keep thumbnail writes scoped to owned video sessions',
      () {
    final rules = File('storage.rules').readAsStringSync();

    expect(rules, contains('function isOwnedThumbnail(fileName)'));
    expect(rules,
        contains("fileName.matches('^thumbnail_[A-Za-z0-9_-]+\\\\.jpg\$')"));
    expect(rules,
        contains('isOwnedVideoDoc(thumbnailDocIdFromJpgFileName(fileName))'));
    expect(rules,
        contains('allow write: if signedIn() && isOwnedThumbnail(fileName);'));
    expect(rules, isNot(contains('allow write: if signedIn();')));
  });
}
