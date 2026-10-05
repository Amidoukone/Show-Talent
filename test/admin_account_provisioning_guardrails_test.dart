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
      expect(source, contains('createdByAdminUid: existingData.createdByAdminUid ??'));
      expect(source, contains('(existingDoc.exists ? null : adminUid)'));
      expect(source, contains('adminCreatedAt: existingData.adminCreatedAt ??'));
    });

    test('managed account smoke covers every admin-provisioned role', () {
      final source = File('scripts/smoke-managed-account-auth-flow.mjs')
          .readAsStringSync();

      for (final role in ['joueur', 'fan', 'club', 'recruteur', 'agent']) {
        expect(source, contains("'$role'"));
      }
      expect(source, contains('adminClaimsAbsent'));
    });

    test('minor invitation can be issued while parental agreement is pending', () {
      final source = File('functions/src/managed_accounts.ts').readAsStringSync();
      expect(
        source,
        contains('if (isMinor && request.data?.guardianConsent != null)'),
      );
      expect(source, contains('status: "pending"'));
      expect(source, contains('minorProfileApproved: guardianApprovalRecorded'));
    });
  });
}
