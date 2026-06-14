import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile advanced CTA stays contextual and mobile-safe', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final profileWidgets =
        File('lib/screens/profile_screen_widgets.dart').readAsStringSync();
    final profileSurface = '$profile\n$profileWidgets';

    expect(profile,
        contains('final hasAdvancedProfile = user.hasAdvancedProfile;'));
    expect(profile, contains('Gardez votre dossier scout'));
    expect(profile, contains("hasAdvancedProfile ? 'Mettre"));
    expect(profile, contains('constraints.maxWidth < 380'));
    expect(profileSurface, contains('maxLines: 2'));
    expect(profileSurface, contains('overflow: TextOverflow.ellipsis'));
    expect(profileSurface, contains('user.isProfileTrusted'));
    expect(profileSurface, contains('Vérifié par Adfoot'));
    expect(
      profileSurface,
      contains('errorBuilder: (_, __, ___) => fallback()'),
    );
    expect(
      profileSurface,
      contains('loadingBuilder: (context, child, loadingProgress)'),
    );
  });
}
