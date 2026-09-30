import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the public projection excludes account secrets and social arrays', () {
    final source = File(
      'functions/src/public_profile_projection.ts',
    ).readAsStringSync();
    final fieldsStart = source.indexOf('const DIRECTORY_FIELDS');
    final fieldsEnd = source.indexOf('] as const;', source.indexOf('const PUBLIC_PROFILE_FIELDS'));
    final allowLists = source.substring(fieldsStart, fieldsEnd);

    for (final forbidden in <String>[
      'fcmToken',
      'email',
      'phone',
      'birthDate',
      'authDisabledReason',
      'followersList',
      'followingsList',
      'acceptedTermsAt',
      'membership',
    ]) {
      expect(allowLists, isNot(contains('"$forbidden"')), reason: forbidden);
    }
  });

  test('full user documents are owner or admin only', () {
    final rules = File('firestore.rules').readAsStringSync();
    final usersStart = rules.indexOf('match /users/{userId}');
    final publicStart = rules.indexOf('match /public_profiles/{userId}');
    final usersRule = rules.substring(usersStart, publicStart);

    expect(
      usersRule,
      contains('allow read: if isOwner(userId) || isAdminOperator();'),
    );
    expect(rules.substring(publicStart), contains('allow write: if false;'));
  });
}
