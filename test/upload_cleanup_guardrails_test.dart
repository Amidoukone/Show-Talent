import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('partial upload cleanup reports unexpected Storage failures', () {
    final repository = _read(
      'lib/services/videos/upload_video_repository.dart',
    );
    final controller = _read('lib/controller/upload_video_controller.dart');

    expect(
      repository,
      contains('Future<void> _deleteIfPresent(Reference ref)'),
    );
    expect(
      repository,
      contains("if (error.code != 'object-not-found') rethrow;"),
    );
    expect(repository, isNot(contains('videoRef.delete().catchError((_) {})')));
    expect(repository, isNot(contains('thumbRef.delete().catchError((_) {})')));
    expect(controller, contains("source: 'upload/cleanup_partial'"));
    // error, not warning: AppLogger samples warnings in production, and a
    // cleanup that silently stops working is exactly the record that must
    // not be sampled away. The line break between `AppLogger.error(` and
    // its message is left free so a pure reformat cannot fail this.
    expect(
      controller,
      matches(RegExp("AppLogger\\.error\\(\\s*'partial upload not cleaned up")),
    );
  });
}
