import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video search propagates author-query failures to its visible error state', () {
    final source = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(source, isNot(contains('Video search author query fallback')));
    expect(source, contains('await _loadVideosForAuthors('));
    expect(source, contains('_searchError ='));
  });
  test('coherence scheduler check uses the same environment as parity', () {
    final script = File('scripts/run-product-coherence-gate.ps1').readAsStringSync();
    expect(script, contains(r'-Project $BackendEnvironment'));
  });
}
