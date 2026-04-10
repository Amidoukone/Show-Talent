import 'package:adfoot/services/users/user_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserRepository.evaluateUserData', () {
    test('flags a missing profile document', () {
      final decision = UserRepository.evaluateUserData(null);

      expect(decision.exists, isFalse);
      expect(decision.issue, UserAccessIssue.missingProfile);
      expect(decision.user, isNull);
      expect(decision.title, 'Compte indisponible');
      expect(decision.message, contains('plus disponible'));
    });

    test('blocks admin portal only roles on mobile', () {
      final decision = UserRepository.evaluateUserData({
        'uid': 'admin-1',
        'nom': 'Admin',
        'email': 'admin@adfoot.org',
        'role': 'admin',
      });

      expect(decision.exists, isTrue);
      expect(decision.issue, UserAccessIssue.adminPortalOnly);
      expect(decision.user?.uid, 'admin-1');
      expect(decision.title, 'Acces refuse');
      expect(decision.message, contains('administration Adfoot'));
    });

    test('blocks disabled or blocked accounts', () {
      final decision = UserRepository.evaluateUserData({
        'uid': 'user-1',
        'nom': 'Blocked User',
        'email': 'blocked@adfoot.org',
        'role': 'joueur',
        'estBloque': false,
        'authDisabled': true,
        'authDisabledReason': 'fraude detectee',
      });

      expect(decision.exists, isTrue);
      expect(decision.issue, UserAccessIssue.blockedOrDisabled);
      expect(decision.title, 'Compte desactive');
      expect(decision.user?.authDisabled, isTrue);
      expect(decision.message, contains('fraude detectee'));
    });

    test('surfaces the admin permanent block reason to the mobile session', () {
      final decision = UserRepository.evaluateUserData({
        'uid': 'user-2',
        'nom': 'Sanctioned User',
        'email': 'sanctioned@adfoot.org',
        'role': 'joueur',
        'estBloque': true,
        'blockMode': 'permanent',
        'authDisabled': false,
        'blockedReason': 'contenu non conforme',
      });

      expect(decision.exists, isTrue);
      expect(decision.issue, UserAccessIssue.blockedOrDisabled);
      expect(decision.title, 'Compte bloque');
      expect(decision.user?.estBloque, isTrue);
      expect(decision.message, contains('contenu non conforme'));
    });

    test('surfaces temporary suspension dates to the mobile session', () {
      final decision = UserRepository.evaluateUserData({
        'uid': 'user-3',
        'nom': 'Suspended User',
        'email': 'suspended@adfoot.org',
        'role': 'joueur',
        'estBloque': true,
        'blockMode': 'temporary',
        'blockedUntil': DateTime.utc(2026, 4, 23, 9, 30).toIso8601String(),
        'authDisabled': false,
        'blockedReason': 'video non adaptee',
      });

      expect(decision.exists, isTrue);
      expect(decision.issue, UserAccessIssue.blockedOrDisabled);
      expect(decision.title, 'Compte suspendu');
      expect(decision.message, contains('23/04/2026'));
      expect(decision.message, contains('video non adaptee'));
    });

    test('ignores expired temporary suspensions', () {
      final decision = UserRepository.evaluateUserData({
        'uid': 'user-4',
        'nom': 'Expired Suspension',
        'email': 'expired@adfoot.org',
        'role': 'joueur',
        'estBloque': true,
        'blockMode': 'temporary',
        'blockedUntil': DateTime.utc(2020, 1, 1).toIso8601String(),
        'authDisabled': false,
      });

      expect(decision.exists, isTrue);
      expect(decision.issue, isNull);
    });

    test('allows managed roles when profile is valid', () {
      for (final role in const ['club', 'recruteur', 'agent']) {
        final decision = UserRepository.evaluateUserData({
          'uid': 'uid-$role',
          'nom': 'Compte $role',
          'email': '$role@adfoot.org',
          'role': role,
          'estBloque': false,
          'authDisabled': false,
        });

        expect(decision.exists, isTrue);
        expect(
          decision.issue,
          isNull,
          reason: 'Le role $role doit pouvoir se connecter sur mobile.',
        );
      }
    });
  });

  test('buildPublicSignupUser keeps public defaults safe', () {
    final user = UserRepository.buildPublicSignupUser(
      uid: 'player-1',
      nom: 'Moussa Traore',
      email: 'moussa@adfoot.org',
      role: 'joueur',
      phone: '70000000',
      now: DateTime.utc(2026, 4, 2, 10),
    );

    expect(user.uid, 'player-1');
    expect(user.role, 'joueur');
    expect(user.estActif, isFalse);
    expect(user.emailVerified, isFalse);
    expect(user.profilePublic, isTrue);
    expect(user.allowMessages, isTrue);
    expect(user.phone, '70000000');
  });

  test('buildPublicSignupUser rejects managed roles', () {
    expect(
      () => UserRepository.buildPublicSignupUser(
        uid: 'club-1',
        nom: 'Club Privilegie',
        email: 'club@adfoot.org',
        role: 'club',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
