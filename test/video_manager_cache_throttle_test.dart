import 'dart:async';

import 'package:adfoot/widgets/video_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoManager manager;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = VideoManager();
    now = DateTime(2026, 3, 13, 12);
    manager.resetCacheSizeThrottleForTests(
      nowProvider: () => now,
      cacheSizeProvider: () async => 0,
    );
  });

  tearDown(() {
    manager.resetCacheSizeThrottleForTests();
  });

  test('cache size scan is throttled for five minutes', () async {
    var scanCount = 0;
    manager.resetCacheSizeThrottleForTests(
      nowProvider: () => now,
      cacheSizeProvider: () async {
        scanCount += 1;
        return 42;
      },
    );

    await manager.checkCacheSizeForTests();
    await manager.checkCacheSizeForTests();

    expect(scanCount, 1);

    now = now.add(const Duration(minutes: 4, seconds: 59));
    await manager.checkCacheSizeForTests();
    expect(scanCount, 1);

    now = now.add(const Duration(seconds: 1));
    await manager.checkCacheSizeForTests();
    expect(scanCount, 2);
  });

  test('cache size scan reuses the in-flight request', () async {
    var scanCount = 0;
    final completer = Completer<int>();

    manager.resetCacheSizeThrottleForTests(
      nowProvider: () => now,
      cacheSizeProvider: () {
        scanCount += 1;
        return completer.future;
      },
    );

    final first = manager.checkCacheSizeForTests();
    final second = manager.checkCacheSizeForTests(force: true);

    expect(scanCount, 1);

    completer.complete(42);
    await Future.wait([first, second]);

    expect(scanCount, 1);
  });

  test('force bypasses the throttle once the previous scan completed',
      () async {
    var scanCount = 0;
    manager.resetCacheSizeThrottleForTests(
      nowProvider: () => now,
      cacheSizeProvider: () async {
        scanCount += 1;
        return 42;
      },
    );

    await manager.checkCacheSizeForTests();
    await manager.checkCacheSizeForTests(force: true);

    expect(scanCount, 2);
  });
}
