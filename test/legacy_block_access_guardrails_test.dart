import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Account access guardrails', () {
    test('firestore rules use authDisabled as the only hard access stop', () {
      final rules = File('firestore.rules').readAsStringSync();

      expect(rules, contains('function hasActiveAccount(uid) {'));
      expect(rules, contains('userDoc(uid).data.authDisabled != true;'));
      expect(rules.contains('hasEffectiveAppBlock'), isFalse);
      expect(rules.contains('request.resource.data.estBloque'), isFalse);
      expect(rules.contains('request.resource.data.blockedReason'), isFalse);
    });

    test(
        'messaging directory filters only admin-only and auth-disabled accounts',
        () {
      final userModel = File('lib/models/user.dart').readAsStringSync();
      final getterStart =
          userModel.indexOf('bool get canAppearInMessagingDirectory');
      expect(getterStart, isNonNegative);
      final getterSnippet = userModel.substring(
        getterStart,
        (getterStart + 220).clamp(0, userModel.length),
      );

      expect(userModel.contains('estBloque'), isFalse);
      expect(getterSnippet, contains('!authDisabled'));
      expect(getterSnippet, contains('!isAdminPortalOnlyRole(role)'));
    });

    test('user repository cleans up legacy block fields on profile writes', () {
      final repository =
          File('lib/services/users/user_repository.dart').readAsStringSync();

      expect(repository, contains("'estBloque': FieldValue.delete()"));
      expect(repository, contains("'blockedReason': FieldValue.delete()"));
      expect(repository, contains("'blockMode': FieldValue.delete()"));
      expect(repository, contains("'authDisabled': false"));
    });
  });
}
