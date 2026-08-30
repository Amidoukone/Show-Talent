import 'dart:io';

import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/legal/terms_acceptance_service.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('the terms gate decides only on an exact version match', () {
    test('a dormant gate lets everyone through', () {
      const config = TermsConfig(
        requiredVersion: '',
        termsUrl: 'https://adfoot.org/legal/terms.html',
        privacyUrl: 'https://adfoot.org/legal/privacy-policy.html',
        effectiveOn: '',
      );

      expect(config.isGateActive, isFalse);
      expect(config.isSatisfiedBy(null), isTrue);
      expect(config.isSatisfiedBy(''), isTrue);
      expect(config.isSatisfiedBy('1.0'), isTrue);
    });

    test('an active gate refuses a missing or different acceptance', () {
      const config = TermsConfig(
        requiredVersion: '1.0',
        termsUrl: 'https://adfoot.org/legal/terms.html',
        privacyUrl: 'https://adfoot.org/legal/privacy-policy.html',
        effectiveOn: '1 septembre 2026',
      );

      expect(config.isGateActive, isTrue);
      expect(config.isSatisfiedBy(null), isFalse);
      expect(config.isSatisfiedBy(''), isFalse);
      expect(config.isSatisfiedBy('   '), isFalse);
      expect(config.isSatisfiedBy('0.9'), isFalse);
      expect(config.isSatisfiedBy('1.1'), isFalse);
      expect(config.isSatisfiedBy('1.0'), isTrue);
      expect(config.isSatisfiedBy('  1.0  '), isTrue);
    });

    // Versions are compared as opaque strings, never ordered: "has this user
    // accepted this text" has no notion of newer or older, and a bad ordering
    // would silently let a stale acceptance satisfy a new document.
    test('a newer accepted version does not satisfy an older requirement', () {
      const config = TermsConfig(
        requiredVersion: '2.0',
        termsUrl: 'x',
        privacyUrl: 'y',
        effectiveOn: '',
      );
      expect(config.isSatisfiedBy('10.0'), isFalse);
      expect(config.isSatisfiedBy('2.0.1'), isFalse);
    });
  });

  group('a malformed config never locks the fleet out', () {
    test('an empty document falls back to the bundled, dormant version', () {
      final config = TermsConfig.fromData(const <String, dynamic>{});
      expect(config.requiredVersion, TermsConfig.bundledVersion);
      expect(config.isGateActive, isFalse);
      expect(config.termsUrl, TermsConfig.bundledTermsUrl);
      expect(config.privacyUrl, TermsConfig.bundledPrivacyUrl);
    });

    test('non-string and blank values are ignored', () {
      final config = TermsConfig.fromData(const <String, dynamic>{
        'requiredVersion': 42,
        'termsUrl': '   ',
        'privacyUrl': null,
      });
      expect(config.requiredVersion, TermsConfig.bundledVersion);
      expect(config.termsUrl, TermsConfig.bundledTermsUrl);
      expect(config.privacyUrl, TermsConfig.bundledPrivacyUrl);
    });

    test('a well-formed document activates the gate', () {
      final config = TermsConfig.fromData(const <String, dynamic>{
        'requiredVersion': '1.0',
        'termsUrl': 'https://adfoot.org/legal/terms.html',
        'effectiveOn': '1 septembre 2026',
      });
      expect(config.isGateActive, isTrue);
      expect(config.requiredVersion, '1.0');
      expect(config.effectiveOn, '1 septembre 2026');
    });
  });

  group('the acceptance is stored, and stored where it does no harm', () {
    test('AppUser round-trips the acceptance through toMap', () {
      final user = AppUser.fromMap(<String, dynamic>{
        'uid': 'u1',
        'nom': 'Adama',
        'role': 'joueur',
        'acceptedTermsVersion': '1.0',
      });

      expect(user.acceptedTermsVersion, '1.0');
      expect(user.toMap()['acceptedTermsVersion'], '1.0');
    });

    // The embedded map is copied verbatim into offer candidates and event
    // participants, and the Firestore rules compare those rows by value to
    // stop one player deleting another's application. A new key here would
    // make a re-serialised row differ from the stored one and turn a
    // legitimate registration into permission-denied.
    test('the acceptance never leaks into the embedded user map', () {
      final user = AppUser.fromMap(<String, dynamic>{
        'uid': 'u1',
        'nom': 'Adama',
        'role': 'joueur',
        'acceptedTermsVersion': '1.0',
      });

      expect(user.toEmbeddedMap().containsKey('acceptedTermsVersion'), isFalse);
      expect(user.toEmbeddedMap().containsKey('acceptedTermsAt'), isFalse);
    });
  });

  group('the gate is wired where it cannot be routed around', () {
    late String mainScreen;
    late String rules;
    late String userRepository;

    setUpAll(() {
      mainScreen = _read('lib/screens/main_screen.dart');
      rules = _read('firestore.rules');
      userRepository = _read('lib/services/users/user_repository.dart');
    });

    test('the shell itself gates, before any tab is built', () {
      final gate = mainScreen.indexOf('_termsConfig.isSatisfiedBy(');
      final tabs = mainScreen.indexOf('body: _destination(_selectedIndex');
      expect(gate, isNonNegative);
      expect(tabs, isNonNegative);
      expect(
        gate,
        lessThan(tabs),
        reason: 'the gate must be evaluated before the tab scaffold is built',
      );
      expect(mainScreen, contains('TermsAcceptanceScreen('));
    });

    test('the acceptance screen cannot be dismissed', () {
      final screen = _read('lib/screens/terms_acceptance_screen.dart');
      expect(screen, contains('canPop: false'));
      expect(
        screen,
        contains('onSignOut'),
        reason: 'refusing must remain possible, by signing out',
      );
    });

    test('the server stamps the acceptance time, not the device', () {
      expect(
        userRepository,
        contains("'acceptedTermsAt': FieldValue.serverTimestamp()"),
      );
      expect(
        rules,
        contains('request.resource.data.acceptedTermsAt == request.time'),
        reason: 'a client-supplied timestamp would make the record worthless',
      );
    });

    test('accepting is its own rule, never a profile update', () {
      expect(rules, contains('function canAcceptOwnTerms()'));
      expect(
        rules,
        contains('changesOnly(["acceptedTermsVersion", "acceptedTermsAt"])'),
      );
      expect(rules, contains('canAcceptOwnTerms() ||'));
      // Folding it into canUpdateOwnProfile would drag consent through the
      // verified-profile invalidation invariant: a user would lose their
      // verified badge for accepting the terms.
      final allowlist = rules.indexOf('function canUpdateOwnProfile()');
      expect(allowlist, isNonNegative);
      final body = rules.substring(allowlist, allowlist + 2600);
      expect(body, isNot(contains('"acceptedTermsVersion"')));
    });
  });
}
