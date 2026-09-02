import 'dart:io';

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

    expect(source, contains('PackageInfo.fromPlatform()'));
    expect(source, contains(r'${info.version}'));
    expect(source, contains(r'${info.buildNumber}'));
    // A version hardcoded here would drift from the artifact the moment the
    // next build is cut, which is the failure this label exists to catch.
    expect(source, isNot(contains('1.0.7')));
    expect(source, isNot(contains('String.fromEnvironment')));
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
