import 'dart:io';

import 'package:adfoot/services/app_version.dart';
import 'package:adfoot/widgets/app_version_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// A tester's phone shows `1.0.7` whether it runs build 29, 30, 31 or 32. This
/// label is what makes "I installed the new one" verifiable, so what it says
/// has to be exact — and it has to come from the installed package, not from a
/// constant compiled in beside it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The reader caches for the whole process; without this, the first test to
    // run would fix the answer for the others.
    AppVersion.resetForTests();
    PackageInfo.setMockInitialValues(
      appName: 'Adfoot',
      packageName: 'org.adfoot.app',
      version: '1.0.7',
      buildNumber: '33',
      buildSignature: '',
    );
  });

  testWidgets('shows the installed version name and build number', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionLabel())),
    );
    await tester.pumpAndSettle();

    // The build number is the half that distinguishes two builds; a label that
    // dropped it would look right and answer nothing.
    expect(find.text('Adfoot 1.0.7 (33)'), findsOneWidget);
  });

  testWidgets('reserves its line before the platform answers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionLabel())),
    );

    // First frame: the platform channel has not answered yet.
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.getSize(find.byType(SizedBox).first).height, 18);

    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
  });

  test('the label reads the package manifest, not a compiled constant', () {
    final source = File('lib/widgets/app_version_label.dart').readAsStringSync();

    // Through AppVersion now, rather than straight to the platform channel:
    // the push-token document and every client_logs entry name the same build,
    // and three independent reads of one manifest is three chances for them to
    // disagree about what the user is running. The guarantee is unchanged --
    // the number still comes from the installed package.
    expect(source, contains('AppVersion.resolve()'));
    expect(source, contains('AppVersion.versionName'));
    expect(source, contains('AppVersion.buildNumber'));

    final reader = File('lib/services/app_version.dart').readAsStringSync();
    expect(reader, contains('PackageInfo.fromPlatform()'));

    // A version hardcoded on either side would drift from the artifact the
    // moment the next build is cut, which is the failure this label exists to
    // catch.
    for (final text in [source, reader]) {
      expect(text, isNot(contains('1.0.7')));
      expect(text, isNot(contains('String.fromEnvironment')));
    }
  });

  test('the settings screen ends with the version', () {
    final settings = File('lib/screens/setting_screen.dart').readAsStringSync();

    expect(settings, contains('const AppVersionLabel()'));
    expect(
      settings,
      contains("import 'package:adfoot/widgets/app_version_label.dart';"),
    );
  });
}
