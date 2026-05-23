import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('admin account provisioning guardrails', () {
    test('provisioning blocks existing Auth users with admin claims', () {
      final source =
          File('functions/src/managed_accounts.ts').readAsStringSync();

      expect(source, contains('isPrivilegedClaims'));
      expect(
        source,
        contains('isPrivilegedClaims(userRecord.customClaims)'),
      );
      expect(
        source,
        contains(
          'Un compte avec claims admin ne peut pas etre provisionne',
        ),
      );
    });

    test('managed account smoke covers every admin-provisioned role', () {
      final source = File('scripts/smoke-managed-account-auth-flow.mjs')
          .readAsStringSync();

      for (final role in ['joueur', 'fan', 'club', 'recruteur', 'agent']) {
        expect(source, contains("'$role'"));
      }
      expect(source, contains('adminClaimsAbsent'));
    });
  });
}
