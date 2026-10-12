import 'package:adfoot/services/app_version.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:flutter/material.dart';

/// The version of the build that is actually installed, name and number.
///
/// Read from the platform package manifest, never from a compile-time
/// constant: the question this answers is "which artifact did Play serve to
/// this phone?", and only the installed package knows. A `--dart-define` or a
/// generated constant would say what the *source* believed at build time,
/// which is the very thing that cannot be trusted here.
///
/// The build number is the whole point. Every build of a release carries the
/// same versionName -- four of them did in a row -- so without the number in
/// brackets nothing on any screen tells two builds apart, and a tester still
/// on an older install cannot be distinguished from a fix that did not work.
/// That confusion cost a full build cycle on 2026-09-02.
///
/// Which is also why no version literal may appear in this file: a guardrail
/// in test/app_version_label_test.dart fails if one does.
class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({super.key});

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Through [AppVersion], not straight to the platform channel: the push
    // token document and every `client_logs` entry now name the same build,
    // and three independent reads of the same manifest is three chances for
    // them to disagree about what the user is running.
    await AppVersion.resolve();

    final version = AppVersion.versionName;
    // Saying nothing would read as "no version", which is exactly the
    // ambiguity this label exists to remove.
    final label = version == null
        ? 'Version indisponible'
        : 'Adfoot $version (${AppVersion.buildNumber ?? '?'})';

    if (!mounted) {
      return;
    }
    setState(() => _label = label);
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label == null) {
      // Hold the line's height so the end of the screen does not jump when the
      // platform channel answers.
      return const SizedBox(height: 18);
    }

    return Center(
      child: SelectableText(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          color: AdColors.onSurfaceMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
