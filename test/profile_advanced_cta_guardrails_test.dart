import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile advanced CTA stays contextual and mobile-safe', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();

    expect(profile,
        contains('final hasAdvancedProfile = user.hasAdvancedProfile;'));
    expect(profile, contains('Gardez votre dossier scout à jour'));
    expect(profile,
        contains("hasAdvancedProfile ? 'Mettre à jour' : 'Compléter'"));
    expect(profile, contains('constraints.maxWidth < 380'));
    expect(profile, contains('maxLines: 2'));
    expect(profile, contains('overflow: TextOverflow.ellipsis'));
    expect(profile, contains('errorBuilder: (_, __, ___) => fallback()'));
    expect(
        profile, contains('loadingBuilder: (context, child, loadingProgress)'));
  });
}
