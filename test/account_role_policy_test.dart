import 'package:adfoot/models/user.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser buildUser(String role) {
  return AppUser(
    uid: 'uid-$role',
    nom: 'User $role',
    email: '$role@example.com',
    role: role,
    photoProfil: '',
    estActif: true,
    emailVerified: true,
    followers: 0,
    followings: 0,
    dateInscription: DateTime(2026, 1, 1),
    dernierLogin: DateTime(2026, 1, 1),
    followersList: const [],
    followingsList: const [],
  );
}

void main() {
  test('public self signup is disabled on mobile', () {
    expect(publicSelfSignupRoles, isEmpty);
    expect(isPublicSelfSignupRole('joueur'), isFalse);
    expect(isPublicSelfSignupRole('fan'), isFalse);
    expect(isPublicSelfSignupRole('club'), isFalse);
    expect(isPublicSelfSignupRole('recruteur'), isFalse);
    expect(isPublicSelfSignupRole('agent'), isFalse);
  });

  test('all business roles are now admin provisioned', () {
    expect(
      adminProvisionedRoles,
      ['joueur', 'fan', 'club', 'recruteur', 'agent'],
    );
  });

  test('managed roles stay server provisioned', () {
    expect(isManagedAccountRole('club'), isTrue);
    expect(isManagedAccountRole('recruteur'), isTrue);
    expect(isManagedAccountRole('agent'), isTrue);
    expect(isManagedAccountRole('joueur'), isFalse);
  });

  test('admin operators stay on the admin project only', () {
    expect(isAdminPortalOnlyRole('admin'), isTrue);
    expect(isAdminPortalOnlyRole('superAdmin'), isFalse);
    expect(isAdminPortalOnlyRole('joueur'), isFalse);
  });

  test('agent is treated like recruiter for professional permissions', () {
    final agent = buildUser('agent');
    final recruiter = buildUser('recruteur');

    expect(agent.isAgent, isTrue);
    expect(agent.isRecruiter, isTrue);
    expect(agent.canPublishOpportunities, isTrue);
    expect(recruiter.canPublishOpportunities, isTrue);
  });
}
