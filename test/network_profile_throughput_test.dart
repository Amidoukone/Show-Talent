import 'dart:io';

import 'package:adfoot/videos/domain/network_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bandwidth tier decides which rendition every video in the feed is
/// played at, how many neighbours are preloaded and how many controllers stay
/// warm — and until this pass it was decided by arithmetic that could only
/// ever answer `high`.
///
/// `_measureThroughput` divided bits by milliseconds, which is already
/// kilobits per second, and then multiplied by a thousand before handing the
/// result to thresholds written in kbps. adfoot-production shows the outcome
/// with no ambiguity at all: over the fourteen days to 2026-08-22, all 63
/// logged playback sessions carried `networkTier: "high"`, and the 1080p
/// sessions among them averaged a 55% rebuffer rate where 720p sat at 4.7%.
String _read(String path) => File(path).readAsStringSync();

/// 256 KB, the payload [NetworkProfileService] asks the CDN for.
const int _probeBytes = 262144;

http.Client _clientDelivering({required Duration transferDelay}) {
  return MockClient((request) async {
    if (request.method == 'HEAD') {
      return http.Response('', 200);
    }
    await Future<void>.delayed(transferDelay);
    return http.Response.bytes(List<int>.filled(_probeBytes, 0), 200);
  });
}

Future<NetworkProfileTier> _tierFor(Duration transferDelay) async {
  SharedPreferences.setMockInitialValues({});
  final service = NetworkProfileService(
    client: _clientDelivering(transferDelay: transferDelay),
    preferences: await SharedPreferences.getInstance(),
  );
  final profile = await service.detectProfile();
  return profile.tier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the measured tier describes the connection', () {
    // The probe times a real transfer, so the first detection in a cold test
    // VM charges JIT warm-up to the connection and reads far slower than the
    // mock delay it was given. Spend that once, up front, where it is not
    // being measured.
    setUpAll(() async {
      await _tierFor(Duration.zero);
    });

    // 2 097 152 bits in 200 ms is ~10 485 kbps. Comfortably clear of the
    // 6 000 kbps bar, which is what "can pull the heaviest rendition we
    // serve" costs once connection setup is left inside the sample.
    test('a fast transfer is high', () async {
      expect(
        await _tierFor(const Duration(milliseconds: 200)),
        NetworkProfileTier.high,
      );
    });

    // ~2 995 kbps: enough for the 480p companion (1.6 Mb/s), not for a 1080p
    // passthrough at 5.2 to 9.7 Mb/s.
    test('a middling transfer is medium', () async {
      expect(
        await _tierFor(const Duration(milliseconds: 700)),
        NetworkProfileTier.medium,
      );
    });

    // ~1 048 kbps. Under the old arithmetic this same transfer reported
    // 1 048 000 and was called `high`.
    test('a slow transfer is low, where it used to be high', () async {
      expect(
        await _tierFor(const Duration(milliseconds: 2000)),
        NetworkProfileTier.low,
      );
    });
  });

  group('the probe is a measurement, not a round trip', () {
    late String source;

    setUpAll(() {
      source = _read('lib/videos/domain/network_profile.dart');
    });

    test('bits per millisecond are reported as kbps, not multiplied again',
        () {
      final start = source.indexOf('Future<double?> _measureThroughput()');
      expect(start, isNonNegative);
      final body = source.substring(start);

      expect(body, contains('(response.bodyBytes.length * 8) / durationMs'));
      expect(
        body,
        isNot(contains('kbps * 1000')),
        reason: 'bits/ms is already kbps; the extra factor is what made every '
            'device report itself as high',
      );
    });

    test('the payload is large enough for the transfer to dominate', () {
      expect(
        source,
        contains('static const int _throughputProbeBytes = 262144;'),
      );
      expect(
        source,
        contains(r"'https://speed.cloudflare.com/__down?bytes=$_throughputProbeBytes'"),
        reason: 'the probe and the arithmetic must agree on the payload',
      );
      expect(
        source,
        isNot(contains('bytes=8000')),
        reason: '8 KB over a warmed connection measures latency, not speed',
      );
    });

    // Reporting `null` for a probe that ran out of budget sent exactly the
    // slowest connections back to the optimistic transport baseline, which is
    // `medium` on both Wi-Fi and mobile.
    test('a probe that runs out of budget reports low, not nothing', () {
      final start = source.indexOf('Future<double?> _measureThroughput()');
      final body = source.substring(start);

      expect(body, contains('if (response.statusCode == _probeTimeoutStatus)'));
      final timeoutBranch = body.substring(
        body.indexOf('if (response.statusCode == _probeTimeoutStatus)'),
      );
      expect(timeoutBranch.indexOf('return 0;'), isNonNegative);
    });

    test('the download probe has its own budget, longer than the HEAD probe',
        () {
      expect(
        source,
        contains(
          'static const Duration _throughputProbeTimeout = Duration(seconds: 4);',
        ),
      );
      final start = source.indexOf('Future<double?> _measureThroughput()');
      final body = source.substring(start);
      expect(body, contains('_throughputProbeTimeout,'));
    });
  });
}
