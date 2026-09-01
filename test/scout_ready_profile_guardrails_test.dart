import 'dart:io';

import 'package:adfoot/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// A player is announced as "Profil Élite" only when a club could actually
/// act on the file.
///
/// The label is not decoration. It is the app telling a recruiter "this one is
/// worth your time", and a recruiter reads a file in twenty seconds: position,
/// foot, build, nationality, club level, contract, minutes played. A file that
/// answers none of those is one no decision can be taken on.
///
/// The age is required, and it is read from `birthYear`, never from
/// `birthDate`. `birthDate` lives in `users/{uid}/private/contact` and reaches
/// only the profile owner, so requiring *that* made the verdict depend on who
/// was reading — the player saw "Élite" while a recruiter saw "partiel" on the
/// same file. `birthYear` is derived server-side onto the public document, so
/// both readers get it and the verdict holds still.
///
/// Requiring it is not a matter of taste: `computeIsSearchable`
/// (functions/src/user_search_fields.ts) refuses a null `birthYear`, so a file
/// without one is invisible to every recruiter search. Announcing it as ready
/// told the player the opposite of what the server was doing.
AppUser _player({
  DateTime? birthDate,
  String? country,
  Map<String, dynamic>? football,
  String? cvUrl,
}) {
  return AppUser.fromMap(<String, dynamic>{
    'uid': 'p1',
    'nom': 'Awa Traore',
    'role': 'joueur',
    'birthDate': ?birthDate?.toIso8601String(),
    'country': ?country,
    'cvUrl': ?cvUrl,
    ...?football,
  });
}

/// Every football fact the rule asks for, in the flat shape the redesign
/// writes: codes at the top level of the user document, because a Firestore
/// query cannot usefully index a field buried in a map.
Map<String, dynamic> _completeFootballFile() {
  return <String, dynamic>{
    // Pose par le trigger `deriveUserSearchFields`, pas par le client : un
    // dossier complet en production en porte toujours un.
    'birthYear': 2007,
    'nationalities': <String>['CI'],
    'positionCodes': <String>['CM'],
    'strongFoot': 'left',
    'heightCm': 178,
    'contractStatus': 'free',
    'currentClubLevel': 'academy',
    'currentSeason': <String, dynamic>{
      'season': '2025-26',
      'competition': 'Ligue 1 CIV',
      'ageCategory': 'U19',
      'minutes': 900,
      'goals': 4,
    },
  };
}

void main() {
  final birthDate = DateTime(2007, 3, 14);

  group('an Élite file can be acted on by a club', () {
    test('a complete file with a country earns the label', () {
      final user = _player(
        country: 'Côte d’Ivoire',
        football: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.hasScoutReadyProfile, isTrue);
      expect(user.profileLevelLabel, 'Profil Élite');
    });

    test('a file the search would not return is never announced as ready', () {
      // La regression que ce test tient : tout etait rempli sauf l'annee de
      // naissance, l'app affichait « Dossier scout pret » en vert, et
      // `computeIsSearchable` mettait `isSearchable` a false. Le joueur se
      // croyait visible et n'apparaissait dans aucune recherche.
      final football = _completeFootballFile()..remove('birthYear');
      final user = _player(
        country: 'Côte d’Ivoire',
        football: football,
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.hasScoutReadyProfile, isFalse);
      expect(user.missingScoutRequirements, <String>['Date de naissance']);
    });

    test('a birth date the server has not derived yet does not count', () {
      // `birthYear` est pose par un trigger, pas par l'ecran d'edition. Entre
      // la saisie et la derivation, le dossier n'est pas encore trouvable :
      // le dire est la seule reponse honnete, et c'est aussi ce qui garde le
      // verdict independant du lecteur -- `birthDate` n'atteint que le
      // titulaire, donc s'en servir ici ferait diverger les deux vues.
      final football = _completeFootballFile()..remove('birthYear');
      final owner = _player(
        birthDate: DateTime(2007, 3, 14),
        country: 'Côte d’Ivoire',
        football: football,
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(owner.hasScoutReadyProfile, isFalse);
      expect(owner.missingScoutRequirements, <String>['Date de naissance']);
    });

    test('the verdict is the same whoever is looking', () {
      // A visitor's AppUser is built from the public document alone. If the
      // two disagree, the rule has started reading a private field again.
      Map<String, dynamic> publicDoc() => <String, dynamic>{
        'uid': 'p1',
        'nom': 'Awa Traore',
        'role': 'joueur',
        'country': 'Côte d’Ivoire',
        'cvUrl': 'https://example.org/cv.pdf',
        ..._completeFootballFile(),
      };

      final asVisitor = AppUser.fromMap(publicDoc());
      final asOwner = AppUser.fromMap(
        publicDoc(),
        privateContact: <String, dynamic>{
          'birthDate': birthDate.toIso8601String(),
          'phone': '+2250700000000',
        },
      );

      expect(asVisitor.hasScoutReadyProfile, asOwner.hasScoutReadyProfile);
      expect(
        asVisitor.missingScoutRequirements,
        asOwner.missingScoutRequirements,
      );
      expect(asVisitor.profileLevelLabel, asOwner.profileLevelLabel);
    });

    test('no country, no label', () {
      final user = _player(
        football: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.hasScoutReadyProfile, isFalse);
      expect(user.missingScoutRequirements, contains('Pays'));
    });

    test('a blank country does not pass for one', () {
      final user = _player(
        country: '   ',
        football: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.hasScoutReadyProfile, isFalse);
    });
  });

  group('every football fact is required on its own', () {
    test('an identity alone is not a scouting file', () {
      final user = _player(country: 'Sénégal');

      expect(user.hasScoutReadyProfile, isFalse);
    });

    test('a file with no evidence is not scout-ready', () {
      final user = _player(
        country: 'Sénégal',
        football: _completeFootballFile(),
      );

      expect(user.hasScoutReadyProfile, isFalse);
      expect(
        user.missingScoutRequirements,
        contains('Une vidéo publiée ou un CV'),
      );
    });

    test('each missing fact is named, one at a time', () {
      const cases = <String, String>{
        'birthYear': 'Date de naissance',
        'positionCodes': 'Poste',
        'strongFoot': 'Pied fort',
        'heightCm': 'Taille',
        'nationalities': 'Nationalité',
        'contractStatus': 'Statut contractuel',
        'currentClubLevel': 'Niveau du club actuel',
        'currentSeason': 'Statistiques de la saison en cours',
      };

      cases.forEach((field, expectedLabel) {
        final football = _completeFootballFile()..remove(field);
        final user = _player(
          country: 'Sénégal',
          football: football,
          cvUrl: 'https://example.org/cv.pdf',
        );

        expect(
          user.missingScoutRequirements,
          <String>[expectedLabel],
          reason: 'removing $field must name exactly "$expectedLabel"',
        );
        expect(user.hasScoutReadyProfile, isFalse);
      });
    });
  });

  group('the old free-text files no longer count as advanced', () {
    test('a player with nothing filled in stays at the basic label', () {
      final user = _player();

      expect(user.hasScoutReadyProfile, isFalse);
      expect(user.profileLevelLabel, 'Profil basique');
    });

    test('a legacy playerProfile document reads as empty', () {
      // The two advanced files in production hold `playerProfile.positions` as
      // free text ("Défense", "Attaquant"). The redesign does not read that
      // shape and does not migrate it: the accounts are test accounts, and
      // guessing whether "Défense" means centre-back or full-back would write
      // an invented fact into a base we present as qualified.
      final user = AppUser.fromMap(<String, dynamic>{
        'uid': 'p1',
        'nom': 'Awa Traore',
        'role': 'joueur',
        'playerProfile': <String, dynamic>{
          'positions': <String>['Attaquant'],
          'skills': <String>['Rapide'],
        },
      });

      expect(user.football.isEmpty, isTrue);
      expect(user.hasAdvancedProfile, isFalse);
      expect(user.profileLevelLabel, 'Profil basique');
    });
  });

  group('the file says what it is still missing', () {
    test('an empty player file names every requirement, identity first', () {
      // The order is the order a recruiter asks in, and the screen renders the
      // list as it comes.
      expect(_player().missingScoutRequirements, <String>[
        'Pays',
        'Date de naissance',
        'Nationalité',
        'Poste',
        'Pied fort',
        'Taille',
        'Statut contractuel',
        'Niveau du club actuel',
        'Statistiques de la saison en cours',
        'Une vidéo publiée ou un CV',
      ]);
    });

    test('a complete file is missing nothing', () {
      final user = _player(
        country: 'Côte d’Ivoire',
        football: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );

      expect(user.missingScoutRequirements, isEmpty);
    });

    test('the decision and the explanation cannot disagree', () {
      // The whole reason `hasScoutReadyProfile` is derived from this list
      // rather than re-deriving the same conditions.
      for (final user in <AppUser>[
        _player(),
        _player(country: 'Mali'),
        _player(country: 'Mali', football: _completeFootballFile()),
        _player(
          country: 'Mali',
          football: _completeFootballFile(),
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
      expect(
        screen,
        contains('if (isOwnProfile && !user.hasScoutReadyProfile)'),
      );
      expect(screen, contains('_MissingScoutRequirements('));
    });

    test('the screen copies the rule instead of restating it', () {
      expect(screen, contains('missing: user.missingScoutRequirements'));

      // No surface may test the underlying fields itself: that is how a screen
      // ends up asking for something the rule stopped requiring.
      for (final source in <String>[screen, widgets]) {
        expect(source, isNot(contains('Date de naissance\',')));
      }
    });

    test('the panel renders nothing when nothing is missing', () {
      expect(
        widgets,
        contains('if (missing.isEmpty) return const SizedBox.shrink();'),
      );
    });

    test('the screen reads the typed profile, not the old map', () {
      expect(screen, contains('final football = user.football;'));
      expect(screen, isNot(contains('user.playerProfile ?? {}')));
    });
  });

  group('the four profile levels are all reachable', () {
    // Le trou attrape ici : `isMvpProfileComplete` lisait encore `position`,
    // le champ libre que plus rien n'ecrit depuis la refonte. « Profil
    // complet » etait donc devenu inatteignable pour tout joueur, et avec lui
    // l'invitation a completer le dossier, qui ne s'affiche que sur un profil
    // complet sans dossier avance.
    test('basique, complet, avance, elite', () {
      expect(_player().profileLevelLabel, 'Profil basique');

      final complete = AppUser.fromMap(<String, dynamic>{
        'uid': 'p1',
        'nom': 'Awa Traore',
        'role': 'joueur',
        'team': 'ASEC Mimosas',
      });
      expect(complete.profileLevelLabel, 'Profil complet');
      expect(complete.shouldPromptAdvancedCompletion, isTrue);

      final advanced = AppUser.fromMap(<String, dynamic>{
        'uid': 'p1',
        'nom': 'Awa Traore',
        'role': 'joueur',
        'team': 'ASEC Mimosas',
        'positionCodes': <String>['CM'],
      });
      expect(advanced.profileLevelLabel, 'Profil avancé');
      expect(advanced.shouldPromptAdvancedCompletion, isFalse);

      final elite = _player(
        country: 'Côte d’Ivoire',
        football: _completeFootballFile(),
        cvUrl: 'https://example.org/cv.pdf',
      );
      expect(elite.profileLevelLabel, 'Profil Élite');
    });
  });

  group('the label speaks of players only', () {
    test('a club with a full file is never Élite', () {
      final club = AppUser.fromMap(<String, dynamic>{
        'uid': 'c1',
        'nom': 'ASEC Mimosas',
        'role': 'club',
        'country': 'Côte d’Ivoire',
        ..._completeFootballFile(),
      });

      expect(club.hasScoutReadyProfile, isFalse);
    });
  });
}
