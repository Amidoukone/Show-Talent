import 'dart:io';

import 'package:adfoot/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// A player is announced as "Profil Élite" only when a club could actually
/// act on the file.
///
/// The label is not decoration. It is the app telling a recruiter "this one is
/// worth your time", and the two questions a European club asks before it
/// looks at a single video are how old the player is and which country they
/// come from: the first decides whether FIFA article 19 forbids the transfer
/// outright, the second decides the work-permit route. A file that answers
/// neither is one no decision can be taken on, however complete the rest is.
///
/// Measured in adfoot-production on 2026-08-31: of the eleven player accounts,
/// **zero** carry a birth date and **zero** carry a country. So this tightening
/// removes the label from nobody today — it stops it being handed out on the
/// first advanced profile somebody fills in.
AppUser _player({
  DateTime? birthDate,
  String? country,
  Map<String, dynamic>? playerProfile,
  String? cvUrl,
}) {
  return AppUser.fromMap(<String, dynamic>{
    'uid': 'p1',
    'nom': 'Awa Traore',
    'role': 'joueur',
    'birthDate': ?birthDate?.toIso8601String(),
    'country': ?country,
    'playerProfile': ?playerProfile,
    'cvUrl': ?cvUrl,
  });
}

/// Everything `hasScoutReadyProfile` asks for *besides* identity: a position,
/// stats, a physical trait and a piece of evidence.
Map<String, dynamic> _completeFootballFile() {
  return <String, dynamic>{
    'physical': <String, dynamic>{'heightCm': 178, 'strongFoot': 'gauche'},
    'positions': <String>['Milieu'],
    'skills': <String>['Passe longue'],
    'stats': <String, dynamic>{'minutes': 900, 'goals': 4},
  };
}

void main() {
  final birthDate = DateTime(2007, 3, 14);

  group('an Élite file can be acted on by a club', () {
    test('a complete file with an age and a country earns the label', () {
      final user = _player(
        birthDate: birthDate,
        country: 'Côte d’Ivoire',
        playerProfile: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.hasScoutReadyProfile, isTrue);
      expect(user.profileLevelLabel, 'Profil Élite');
    });

    test('no birth date, no label', () {
      // Article 19 turns on the date, not on how good the video is.
      final user = _player(
        country: 'Côte d’Ivoire',
        playerProfile: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.hasScoutReadyProfile, isFalse);
    });

    test('no country, no label', () {
      final user = _player(
        birthDate: birthDate,
        playerProfile: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.hasScoutReadyProfile, isFalse);
    });

    test('a blank country does not pass for one', () {
      final user = _player(
        birthDate: birthDate,
        country: '   ',
        playerProfile: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.hasScoutReadyProfile, isFalse);
    });
  });

  group('the football file is still required on its own', () {
    test('an age and a country alone are not a scouting file', () {
      // The tightening adds a condition; it must not replace the others.
      final user = _player(birthDate: birthDate, country: 'Sénégal');

      expect(user.hasScoutReadyProfile, isFalse);
    });

    test('a file with no evidence is not scout-ready', () {
      final user = _player(
        birthDate: birthDate,
        country: 'Sénégal',
        playerProfile: _completeFootballFile(),
      );

      expect(user.hasScoutReadyProfile, isFalse);
    });

    test('a file with no position is not scout-ready', () {
      final profile = _completeFootballFile()..remove('positions');

      final user = _player(
        birthDate: birthDate,
        country: 'Sénégal',
        playerProfile: profile,
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.hasScoutReadyProfile, isFalse);
    });
  });

  group('the accounts already in production are unaffected', () {
    test('a player with nothing filled in stays at the basic label', () {
      final user = _player();

      expect(user.hasScoutReadyProfile, isFalse);
      expect(user.profileLevelLabel, 'Profil basique');
    });

    test('the two advanced files in production do not become Élite', () {
      // Both were filled with a position only — no birth date, no country,
      // no stats, and that is the shape this guardrail has to hold.
      final user = _player(
        playerProfile: <String, dynamic>{
          'positions': <String>['Attaquant'],
        },
      );

      expect(user.hasScoutReadyProfile, isFalse);
      expect(user.profileLevelLabel, 'Profil avancé');
    });
  });

  group('the file says what it is still missing', () {
    test('an empty player file names every requirement, identity first', () {
      // The order is the order a recruiter asks in, and the screen renders
      // the list as it comes.
      expect(_player().missingScoutRequirements, <String>[
        'Date de naissance',
        'Pays',
        'Poste',
        'Taille, poids ou pied fort, ou qualités clés',
        'Statistiques de la saison',
        'Une vidéo publiée ou un CV',
      ]);
    });

    test('a complete file is missing nothing', () {
      final user = _player(
        birthDate: birthDate,
        country: 'Côte d’Ivoire',
        playerProfile: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.missingScoutRequirements, isEmpty);
    });

    test('it names exactly what is absent, and nothing else', () {
      final user = _player(
        country: 'Sénégal',
        playerProfile: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.missingScoutRequirements, <String>['Date de naissance']);
    });

    test('the decision and the explanation cannot disagree', () {
      // The whole reason `hasScoutReadyProfile` is derived from this list
      // rather than re-deriving the same conditions.
      for (final user in <AppUser>[
        _player(),
        _player(birthDate: birthDate),
        _player(birthDate: birthDate, country: 'Mali'),
        _player(
          birthDate: birthDate,
          country: 'Mali',
          playerProfile: _completeFootballFile(),
        ),
        _player(
          birthDate: birthDate,
          country: 'Mali',
          playerProfile: _completeFootballFile(),
          cvUrl: 'https://example.org/cv.pdf',
        ),
      ]) {
        expect(
          user.hasScoutReadyProfile,
          user.missingScoutRequirements.isEmpty,
          reason: 'ready must mean nothing is missing, and the reverse',
        );
      }
    });

    test('a non-player is never asked for a scouting file', () {
      final club = AppUser.fromMap(<String, dynamic>{
        'uid': 'c2',
        'nom': 'ASEC Mimosas',
        'role': 'club',
      });

      expect(club.missingScoutRequirements, isEmpty);
      expect(club.hasScoutReadyProfile, isFalse);
    });
  });

  group('the profile screen shows the list, and only to its owner', () {
    final screen = _read('lib/screens/profile_screen.dart');
    final widgets = _read('lib/screens/profile_screen_widgets.dart');

    test('the missing list is guarded by isOwnProfile', () {
      // A visitor seeing "still missing: date of birth, country" is noise for
      // a recruiter and a list of the player's gaps shown to strangers.
      expect(
        screen,
        contains('if (isOwnProfile && !user.hasScoutReadyProfile)'),
      );
      expect(screen, contains('_MissingScoutRequirements('));
    });

    test('the screen copies the rule instead of restating it', () {
      expect(screen, contains('missing: user.missingScoutRequirements'));

      // No surface may test the underlying fields itself: that is how a
      // screen ends up asking for something the rule stopped requiring.
      for (final source in <String>[screen, widgets]) {
        expect(source, isNot(contains("playerProfile!['stats']")));
        expect(source, isNot(contains('Date de naissance\',')));
      }
    });

    test('the panel renders nothing when nothing is missing', () {
      expect(widgets, contains('if (missing.isEmpty) return const SizedBox.shrink();'));
    });
  });

  group('the label speaks of players only', () {
    test('a club with a full file is never Élite', () {
      final club = AppUser.fromMap(<String, dynamic>{
        'uid': 'c1',
        'nom': 'ASEC Mimosas',
        'role': 'club',
        'birthDate': birthDate.toIso8601String(),
        'country': 'Côte d’Ivoire',
        'playerProfile': _completeFootballFile(),
      });

      expect(club.hasScoutReadyProfile, isFalse);
    });
  });
}
