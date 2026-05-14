import 'package:adfoot/models/contact_intake.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Contact intake model', () {
    test('parses guided contact payload safely', () {
      final intake = ContactIntake.fromMap(
        <String, dynamic>{
          'requesterUid': 'club-1',
          'targetUid': 'player-1',
          'requesterRole': 'club',
          'targetRole': 'joueur',
          'contextType': 'event',
          'contextId': 'event-42',
          'contextTitle': 'Detection U19',
          'contactReason': 'trial',
          'introMessage': 'Nous souhaitons vous observer lors de notre stage.',
          'status': 'new',
          'agencyFollowUpStatus': 'new',
          'conversationId': 'club-1__player-1',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 4, 10, 12)),
        },
        fallbackId: 'intake-1',
      );

      expect(intake.id, 'intake-1');
      expect(intake.contextType, ContactContextType.event);
      expect(intake.contactReason, ContactReasonCode.trial);
      expect(intake.contextTitle, 'Detection U19');
      expect(intake.conversationId, 'club-1__player-1');
      expect(intake.createdAt?.year, 2026);
    });

    test('normalizes labels for reasons and context types', () {
      expect(
        ContactIntake.reasonLabel(ContactReasonCode.opportunity),
        'Opportunité',
      );
      expect(
        ContactIntake.reasonLabel('unknown'),
        'Information',
      );
      expect(
        ContactContext.labelForType(ContactContextType.profile),
        'Profil',
      );
      expect(
        ContactContext.labelForType('random'),
        'Contact',
      );
    });

    test('normalizes agency follow-up statuses beyond the initial lead state',
        () {
      expect(
        ContactIntake.normalizeAgencyFollowUpStatus('reviewing'),
        AgencyFollowUpStatus.reviewing,
      );
      expect(
        ContactIntake.normalizeAgencyFollowUpStatus('in_progress'),
        AgencyFollowUpStatus.inProgress,
      );
      expect(
        ContactIntake.agencyFollowUpLabel(AgencyFollowUpStatus.qualified),
        'Qualifié',
      );
      expect(
        ContactIntake.agencyFollowUpLabel('unknown'),
        'Nouveau lead',
      );
    });
  });
}
