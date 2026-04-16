import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Firestore chat/offre/event guardrails', () {
    test(
        'rules keep guided messaging intake creation available to active users',
        () {
      final rules = File('firestore.rules').readAsStringSync();

      expect(rules, contains('match /conversations/{conversationId} {'));
      expect(rules, contains('match /contact_intakes/{intakeId} {'));
      expect(rules,
          contains('request.resource.data.requesterUid == request.auth.uid'));
      expect(rules,
          contains('request.resource.data.agencyFollowUpStatus == "new"'));
    });

    test(
        'rules allow player-side candidature and registration mutations only on narrow fields',
        () {
      final rules = File('firestore.rules').readAsStringSync();

      expect(rules, contains('function canMutateOfferCandidates() {'));
      expect(rules, contains('changesOnly(["candidats", "lastUpdated"])'));
      expect(rules, contains('function canMutateEventParticipants() {'));
      expect(rules, contains('changesOnly(["participants", "lastUpdated"])'));
      expect(rules, contains('resource.data.statut == "ouverte"'));
      expect(rules, contains('resource.data.statut == "ouvert"'));
    });

    test(
        'rules keep offer view metrics writable without reopening owner fields',
        () {
      final rules = File('firestore.rules').readAsStringSync();

      expect(rules, contains('function canMutateOfferViews() {'));
      expect(
          rules, contains('changesOnly(["vues", "viewedBy", "lastUpdated"])'));
    });
  });
}
