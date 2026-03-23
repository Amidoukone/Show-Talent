import 'dart:async';

import 'package:adfoot/videos/domain/network_profile.dart';
import 'package:adfoot/widgets/video_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestNetworkProfileService extends NetworkProfileService {
  TestNetworkProfileService(this._detectProfile);

  final Future<NetworkProfile> Function() _detectProfile;
  int callCount = 0;

  @override
  Future<NetworkProfile> detectProfile() {
    callCount += 1;
    return _detectProfile();
  }
}

Future<void> flushMicrotasks([int times = 3]) async {
  for (int i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoManager manager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = VideoManager();
    manager.resetNetworkProfileStateForTests();
  });

  tearDown(() {
    manager.resetNetworkProfileStateForTests();
  });

  test('bootstrap profile is available before async detection completes',
      () async {
    final completer = Completer<NetworkProfile>();
    final service = TestNetworkProfileService(() => completer.future);

    manager.resetNetworkProfileStateForTests(
      networkProfileService: service,
    );

    expect(manager.currentProfile?.tier, NetworkProfileTier.medium);
    expect(manager.currentProfile?.preferHls, isFalse);

    unawaited(manager.warmNetworkProfile());
    await flushMicrotasks();

    expect(service.callCount, 1);
    expect(manager.currentProfile?.tier, NetworkProfileTier.medium);

    completer.complete(
      const NetworkProfile(
        tier: NetworkProfileTier.high,
        hasConnection: true,
        preferHls: true,
      ),
    );
    await flushMicrotasks();

    expect(manager.currentProfile?.tier, NetworkProfileTier.high);
    expect(manager.currentProfile?.preferHls, isTrue);
  });

  test('warmNetworkProfile reuses the in-flight detection request', () async {
    final completer = Completer<NetworkProfile>();
    final service = TestNetworkProfileService(() => completer.future);

    manager.resetNetworkProfileStateForTests(
      networkProfileService: service,
    );

    unawaited(manager.warmNetworkProfile());
    unawaited(manager.warmNetworkProfile());
    await flushMicrotasks();

    expect(service.callCount, 1);

    completer.complete(
      const NetworkProfile(
        tier: NetworkProfileTier.low,
        hasConnection: true,
      ),
    );
    await flushMicrotasks();

    expect(manager.currentProfile?.tier, NetworkProfileTier.low);
  });

  test('initializeController does not block on network profile detection',
      () async {
    final completer = Completer<NetworkProfile>();
    final service = TestNetworkProfileService(() => completer.future);

    manager.resetNetworkProfileStateForTests(
      networkProfileService: service,
    );

    final result = await Future.any<String>([
      manager
          .initializeController(
            'test-context',
            '',
            sources: const [],
          )
          .then((_) => 'success')
          .catchError((_) => 'error'),
      Future<String>.delayed(
        const Duration(milliseconds: 150),
        () => 'timeout',
      ),
    ]);

    expect(result, 'error');
    expect(service.callCount, 1);
    expect(manager.currentProfile?.tier, NetworkProfileTier.medium);

    completer.complete(
      const NetworkProfile(
        tier: NetworkProfileTier.low,
        hasConnection: true,
      ),
    );
    await flushMicrotasks();
  });

  test('uiRevision changes when load state changes', () async {
    final initialRevision = manager.uiRevision.value;

    await expectLater(
      manager.initializeController(
        'test-context',
        '',
        sources: const [],
      ),
      throwsException,
    );

    expect(
      manager.getLoadState('test-context', ''),
      VideoLoadState.errorSource,
    );
    expect(manager.uiRevision.value, greaterThan(initialRevision));
  });

  test('scoped UI watchers only tick for the matching video URL', () async {
    final watched = manager.watchVideoUi('test-context', '');
    final other = manager.watchVideoUi('test-context', 'other');

    final watchedInitial = watched.value;
    final otherInitial = other.value;

    await expectLater(
      manager.initializeController(
        'test-context',
        '',
        sources: const [],
      ),
      throwsException,
    );

    expect(watched.value, greaterThan(watchedInitial));
    expect(other.value, otherInitial);

    manager.unwatchVideoUi('test-context', '');
    manager.unwatchVideoUi('test-context', 'other');
  });

  test('enforceLimit ignores missing contexts after disposal', () async {
    await manager.disposeAllForContext('gone-context');

    await expectLater(
      manager.enforceLimitForTests('gone-context'),
      completes,
    );
  });
}
