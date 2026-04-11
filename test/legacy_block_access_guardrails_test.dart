import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Legacy block access guardrails', () {
    test('firestore rules keep mobile reads compatible with legacy block flags',
        () {
      final rules = File('firestore.rules').readAsStringSync();

      expect(
        rules,
        contains('function hasActiveAccount(uid) {'),
      );
      expect(
        rules,
        contains('userDoc(uid).data.authDisabled != true;'),
      );
      expect(
        rules.contains('!hasEffectiveAppBlock(userDoc(uid).data)'),
        isFalse,
      );
      expect(
        rules,
        contains('function expectedVerifiedActiveState() {'),
      );
      expect(
        rules.contains('!hasEffectiveAppBlock(request.resource.data)'),
        isFalse,
      );
    });

    test('messaging directory no longer hides users only because estBloque is set',
        () {
      final userModel = File('lib/models/user.dart').readAsStringSync();
      final getterStart =
          userModel.indexOf('bool get canAppearInMessagingDirectory');
      expect(getterStart, isNonNegative);
      final getterSnippet = userModel.substring(
        getterStart,
        (getterStart + 220).clamp(0, userModel.length),
      );

      expect(userModel, contains('bool get canAppearInMessagingDirectory'));
      expect(getterSnippet.contains('!estBloque'), isFalse);
      expect(getterSnippet, contains('!authDisabled'));
      expect(getterSnippet, contains('!isAdminPortalOnlyRole(role)'));
    });
  });
}
