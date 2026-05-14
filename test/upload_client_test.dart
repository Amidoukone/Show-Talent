import 'dart:io';

import 'package:adfoot/services/videos/data/upload_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

typedef PutHandler = Future<Response<dynamic>> Function(
  String path, {
  Object? data,
  Options? options,
  CancelToken? cancelToken,
});

class TestUploadHttpClient implements UploadHttpClient {
  TestUploadHttpClient(this._handler);

  final PutHandler _handler;

  @override
  Future<Response<dynamic>> put(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _handler(
      path,
      data: data,
      options: options,
      cancelToken: cancelToken,
    );
  }
}

Response<dynamic> buildResponse(
  int statusCode, {
  Map<String, List<String>> headers = const {},
}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: 'https://upload.example.com'),
    statusCode: statusCode,
    headers: Headers.fromMap(headers),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory('test/.tmp/upload_client');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> createFile(String name, List<int> bytes) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  UploadSessionState buildSession() {
    return UploadSessionState(
      sessionId: 'session-1',
      uploadUrl: 'https://upload.example.com/video',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      videoPath: 'videos/session-1.mp4',
      thumbnailPath: 'thumbnails/session-1.jpg',
      localFilePath: '${tempDir.path}/video.mp4',
    );
  }

  ThumbnailUploadTicket buildTicket() {
    return ThumbnailUploadTicket(
      uploadUrl: 'https://upload.example.com/thumb',
      thumbnailPath: 'thumbnails/session-1.jpg',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      expectedSize: 4,
      expectedHash: 'hash',
      contentType: 'image/jpeg',
    );
  }

  test('uploadFile accepts 200, 201 and 204 terminal statuses', () async {
    for (final statusCode in const [200, 201, 204]) {
      final file = await createFile('video_$statusCode.bin', [1, 2, 3, 4]);
      final progressValues = <double>[];

      final client = UploadClient(
        httpClient: TestUploadHttpClient(
          (path, {data, options, cancelToken}) async {
            final contentRange = options?.headers?['Content-Range'] as String?;
            if (contentRange == 'bytes */4') {
              return buildResponse(400);
            }
            return buildResponse(statusCode);
          },
        ),
        cachePathProvider: () async =>
            '${tempDir.path}/session_$statusCode.json',
        videoRetryDelay: Duration.zero,
        maxChunkRetries: 2,
      );

      final uploaded = await client.uploadFile(
        session: buildSession(),
        file: file,
        onProgress: progressValues.add,
      );

      expect(uploaded, isTrue);
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, 1.0);
    }
  });

  test('uploadFile continues after 308 and completes on final 200', () async {
    final file = await createFile(
      'video_large.bin',
      List<int>.generate(1024 * 1024 + 16, (index) => index % 255),
    );
    final progressValues = <double>[];
    var uploadCalls = 0;

    final client = UploadClient(
      httpClient: TestUploadHttpClient(
        (path, {data, options, cancelToken}) async {
          final contentRange = options?.headers?['Content-Range'] as String?;
          if (contentRange == 'bytes */1048592') {
            return buildResponse(400);
          }

          uploadCalls += 1;
          if (uploadCalls == 1) {
            return buildResponse(
              308,
              headers: const {
                'range': ['bytes=0-1048575'],
              },
            );
          }

          return buildResponse(200);
        },
      ),
      cachePathProvider: () async => '${tempDir.path}/session_resume.json',
      videoRetryDelay: Duration.zero,
      maxChunkRetries: 2,
    );

    final uploaded = await client.uploadFile(
      session: buildSession(),
      file: file,
      onProgress: progressValues.add,
    );

    expect(uploaded, isTrue);
    expect(uploadCalls, 2);
    expect(progressValues.last, 1.0);
  });

  test('uploadFile rejects unexpected 400 after bounded retries', () async {
    final file = await createFile('video_error.bin', [1, 2, 3, 4]);
    var uploadAttempts = 0;

    final client = UploadClient(
      httpClient: TestUploadHttpClient(
        (path, {data, options, cancelToken}) async {
          final contentRange = options?.headers?['Content-Range'] as String?;
          if (contentRange == 'bytes */4') {
            return buildResponse(400);
          }

          uploadAttempts += 1;
          return buildResponse(400);
        },
      ),
      cachePathProvider: () async => '${tempDir.path}/session_error.json',
      videoRetryDelay: Duration.zero,
      maxChunkRetries: 2,
    );

    await expectLater(
      () => client.uploadFile(
        session: buildSession(),
        file: file,
        onProgress: (_) {},
      ),
      throwsA(
        isA<UploadClientException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having(
              (e) => e.message,
              'message',
              contains('après 2 tentatives'),
            ),
      ),
    );

    expect(uploadAttempts, 2);
  });

  test('uploadThumbnailFile accepts 204 and rejects 404 after retries',
      () async {
    final file = await createFile('thumb.bin', [1, 2, 3, 4]);
    var failingAttempts = 0;

    final successClient = UploadClient(
      httpClient: TestUploadHttpClient(
        (path, {data, options, cancelToken}) async => buildResponse(204),
      ),
      thumbnailRetryDelay: Duration.zero,
      maxChunkRetries: 2,
    );

    final uploaded = await successClient.uploadThumbnailFile(
      ticket: buildTicket(),
      file: file,
      onProgress: (_) {},
    );

    expect(uploaded, isTrue);

    final failingClient = UploadClient(
      httpClient: TestUploadHttpClient(
        (path, {data, options, cancelToken}) async {
          failingAttempts += 1;
          return buildResponse(404);
        },
      ),
      thumbnailRetryDelay: Duration.zero,
      maxChunkRetries: 2,
    );

    await expectLater(
      () => failingClient.uploadThumbnailFile(
        ticket: buildTicket(),
        file: file,
        onProgress: (_) {},
      ),
      throwsA(
        isA<UploadClientException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', contains('miniature')),
      ),
    );

    expect(failingAttempts, 2);
  });
}
