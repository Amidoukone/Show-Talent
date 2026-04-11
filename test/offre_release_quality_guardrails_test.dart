import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Offre release quality guardrails', () {
    test('offre form awaits controller result before success feedback', () {
      final form = File('lib/screens/offres_form.dart').readAsStringSync();

      expect(form, contains('Future<void> _submitForm() async'));
      expect(form, contains('await offreController.modifierOffre'));
      expect(form, contains('await offreController.publierOffre'));
      expect(form, contains('if (!response.success)'));
      expect(form, contains('AdFeedback.error('));
      expect(form, contains('AdFeedback.success('));
    });

    test('offre screen reacts to action responses for status, apply and delete',
        () {
      final screen = File('lib/screens/offre_screen.dart').readAsStringSync();

      expect(screen, contains('await offreController.changerStatut'));
      expect(screen, contains('await offreController.postulerOffre'));
      expect(screen, contains('await offreController.seDesinscrireOffre'));
      expect(screen, contains('await offreController.supprimerOffre'));
      expect(screen, contains('response.showToast(includeSuccess: true);'));
      expect(screen, contains('response.message'));
    });

    test('offre controller mutations return explicit action responses', () {
      final controller =
          File('lib/controller/offre_controller.dart').readAsStringSync();

      expect(controller, contains('Future<ActionResponse> publierOffre'));
      expect(controller, contains('Future<ActionResponse> modifierOffre'));
      expect(controller, contains('Future<ActionResponse> changerStatut'));
      expect(controller, contains('Future<ActionResponse> supprimerOffre'));
      expect(controller, contains('Future<ActionResponse> postulerOffre'));
      expect(controller, contains('Future<ActionResponse> seDesinscrireOffre'));
      expect(controller, contains('runTransaction'));
      expect(controller, contains('_extractCandidateMaps'));
    });

    test('offre controller keeps the mobile stream tolerant and sorted client-side',
        () {
      final controller =
          File('lib/controller/offre_controller.dart').readAsStringSync();

      expect(controller, contains("collection('offres').snapshots()"));
      expect(controller, contains('_parseSnapshotDocs(snapshot.docs)'));
      expect(controller, contains('Offre ignoree car document invalide'));
      expect(controller, contains('fetched.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));'));
    });
  });
}
