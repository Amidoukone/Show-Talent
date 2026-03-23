import 'package:adfoot/widgets/video_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoManager manager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = VideoManager();
  });

  test('preload order favors forward navigation by default', () {
    expect(
      manager.preloadOrderForTests(
        totalVideos: 6,
        index: 2,
        radius: 2,
      ),
      [3, 1, 4, 0],
    );
  });

  test('preload order can favor backward navigation when user scrolls up', () {
    expect(
      manager.preloadOrderForTests(
        totalVideos: 6,
        index: 2,
        radius: 2,
        preferForward: false,
      ),
      [1, 3, 0, 4],
    );
  });

  test('preload order skips out of bounds neighbors cleanly', () {
    expect(
      manager.preloadOrderForTests(
        totalVideos: 4,
        index: 0,
        radius: 2,
      ),
      [1, 2],
    );

    expect(
      manager.preloadOrderForTests(
        totalVideos: 4,
        index: 3,
        radius: 2,
        preferForward: false,
      ),
      [2, 1],
    );
  });
}
