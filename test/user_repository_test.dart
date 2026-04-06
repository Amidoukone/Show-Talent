import 'package:adfoot/services/users/user_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserRepository.evaluateUserData', () {
    test('flags a missing profile document', () {
      final decision = UserRepository.evaluateUserData(null);

      expect(decision.exists, isFalse);
      expect(decision.issue, UserAccessIssue.missingProfile);
      expect(decision.user, isNull);
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
    });

    test('blocks disabled or blocked accounts', () {
      final decision = UserRepository.evaluateUserData({
        'uid': 'user-1',
        'nom': 'Blocked User',
        'email': 'blocked@adfoot.org',
        'role': 'joueur',
        'estBloque': false,
        'authDisabled': true,
      });

      expect(decision.exists, isTrue);
      expect(decision.issue, UserAccessIssue.blockedOrDisabled);
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
