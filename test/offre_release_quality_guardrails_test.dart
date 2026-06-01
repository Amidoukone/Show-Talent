import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Offre release quality guardrails', () {
    test('offre form awaits controller result before system feedback', () {
      final form = File('lib/screens/offres_form.dart').readAsStringSync();

      expect(form, contains('Future<void> _submitForm() async'));
      expect(form, contains('await offreController.modifierOffre'));
      expect(form, contains('await offreController.publierOffre'));
      expect(form, contains('if (!response.success)'));
      expect(form, contains('AdFeedback.error('));
      expect(form, isNot(contains('AdFeedback.success(')));
      expect(form, contains('Offre.normalizeStatus(editingOffre!.statut)'));
      expect(form, contains('class OffreFormResult'));
      expect(form, contains('toRouteArguments()'));
      expect(form, contains('offerSystemNoticeMessage'));
      expect(form, contains('PopScope<void>'));
      expect(form, contains('_handleBackNavigation()'));
      expect(form, contains('AdDialogs.confirm('));
      expect(form, contains('_buildFormSection('));
      expect(form, contains('child: Center('));
      expect(
        form,
        contains('constraints: const BoxConstraints(maxWidth: 720)'),
      );
      expect(form, contains('width: double.infinity'));
      expect(form, contains('_validateTitle'));
      expect(form, contains('_validateDescription'));
      expect(form, contains('_validateOptionalUrl'));
      expect(form, contains('maxLength: _maxTitleLength'));
      expect(form, contains('maxLength: _maxDescriptionLength'));
      expect(form, contains('bool get _hasUnsavedChanges'));
      expect(form, contains('bool _isSubmitting = false;'));
      expect(form, contains('bool _hasCompletedSubmit = false;'));
      expect(form, contains('bool get _submitLocked'));
      expect(form, contains('onPressed: _submitLocked ? null : _submitForm'));
      expect(
          form, contains("id: isEditing ? editingOffre!.id : _draftOfferId"));
      expect(
          form, contains('_navigateAfterSuccessfulSubmit(response.message)'));
      expect(form, contains('Get.closeCurrentSnackbar();'));
      expect(form, contains('Get.back(result: result);'));
      expect(form, isNot(contains('Get.back(result: true);')));
      expect(form, contains('Get.offAllNamed('));
      expect(form, contains('AppRoutes.main'));
      expect(form, contains("'tab': 1"));
      expect(form, contains('_resolveInitialDate('));
    });

    test('offre screen reacts to action responses for status, apply and delete',
        () {
      final screen = File('lib/screens/offre_screen.dart').readAsStringSync();

      expect(screen, contains('await _runOfferAction('));
      expect(screen, contains('offreController.changerStatut('));
      expect(screen, contains('offreController.postulerOffre('));
      expect(screen, contains('offreController.seDesinscrireOffre('));
      expect(screen, contains('offreController.supprimerOffre('));
      expect(screen, contains('_handleActionResponse('));
      expect(screen, contains('_showSystemNotice('));
      expect(screen,
          contains("import 'package:adfoot/widgets/ad_system_notice.dart';"));
      expect(screen, contains('AdSystemNotice('));
      expect(screen, isNot(contains('class _OfferSystemNotice')));
      expect(screen, contains('_buildOffersOverview('));
      expect(screen, contains('_openCreateOfferForm()'));
      expect(screen, contains('_openEditOfferForm(Offre offre)'));
      expect(screen, contains('_pendingOfferActions'));
      expect(screen, contains('_runOfferAction('));
      expect(screen, contains('_isOfferActionPending('));
      expect(screen, contains('_showOfferDetails('));
      expect(screen, contains('Get.bottomSheet('));
      expect(screen, contains('_onlyMine'));
      expect(screen, contains('_onlyExpiringSoon'));
      expect(screen, contains('_isExpired(Offre offre)'));
      expect(screen, contains('_isExpiringSoon(Offre offre)'));
      expect(screen, contains('_isOfferOpenForApplications(Offre offre)'));
      expect(screen, contains('o.recruteur.nom.toLowerCase()'));
      expect(screen, contains('Icons.mark_email_unread_outlined'));
      expect(screen, contains('Créer une offre'));
      expect(
          screen, isNot(contains('response.showToast(includeSuccess: true);')));
      expect(screen, isNot(contains('AdFeedback.success(')));
      expect(screen, contains('response.message'));
      expect(screen, contains('ContactContext.offer('));
      expect(screen, contains('startGuidedConversation('));
      expect(screen, contains('findExistingConversationId('));
      expect(
        screen,
        contains('_buildEmptyState(currentUser, filteredOut: true)'),
      );
      expect(screen, contains('_resetFilters()'));
      expect(screen, contains("arguments: {'tab': 0}"));
    });

    test('system notice is shared outside the offer screen', () {
      final notice =
          File('lib/widgets/ad_system_notice.dart').readAsStringSync();

      expect(notice, contains('enum AdSystemNoticeTone'));
      expect(notice, contains('class AdSystemNoticeData'));
      expect(notice, contains('class AdSystemNotice extends StatelessWidget'));
      expect(notice, contains('AdSystemNoticeTone.success'));
      expect(notice, contains('AdSystemNoticeTone.info'));
      expect(notice, contains('AdSystemNoticeTone.warning'));
      expect(notice, contains('AdSystemNoticeTone.error'));
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

    test(
        'offre controller keeps the mobile stream tolerant and sorted client-side',
        () {
      final controller =
          File('lib/controller/offre_controller.dart').readAsStringSync();

      expect(controller, contains("collection('offres').snapshots()"));
      expect(controller, contains('_parseSnapshotDocs(snapshot.docs)'));
      expect(controller, contains('Offre ignoree car document invalide'));
      expect(
          controller,
          contains(
              'fetched.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));'));
    });
  });
}
