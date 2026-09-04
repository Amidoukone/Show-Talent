import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Le vocabulaire footballistique etait ecrit par le formulaire, affiche par
  // la fiche, et le fil ne savait le trier que par une recherche plein texte
  // sur les libelles. Le poste passe cote serveur ; l'index qui le sert doit
  // exister, et rester declare : une forme de requete sans index ne leve pas,
  // Firestore repond `failed-precondition` et l'ecran parait simplement vide.
  group('le fil des offres trie par vocabulaire footballistique', () {
    test('l’index qui sert le filtre par poste est declare', () {
      final raw = File('firestore.indexes.json').readAsStringSync();
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final indexes = (parsed['indexes'] as List).cast<Map<String, dynamic>>();

      final matching = indexes.where((index) {
        if (index['collectionGroup'] != 'offres') return false;
        final fields = (index['fields'] as List).cast<Map<String, dynamic>>();
        if (fields.length != 2) return false;
        return fields.first['fieldPath'] == 'positionCodes' &&
            fields.first['arrayConfig'] == 'CONTAINS' &&
            fields.last['fieldPath'] == 'dateCreation' &&
            fields.last['order'] == 'DESCENDING';
      });

      expect(
        matching,
        hasLength(1),
        reason: 'sans lui, filtrer par poste rend un fil vide sans erreur',
      );
    });

    test('le depot ne filtre au serveur que sur un seul champ tableau', () {
      final repository = File(
        'lib/services/offers/offer_repository.dart',
      ).readAsStringSync();

      expect(repository, contains("arrayContainsAny: filter.positionCodesForQuery"));
      // `ageCategories` est un second champ tableau : Firestore n'en accepte
      // qu'un par index composite, et le mettre ici ferait echouer la requete.
      expect(repository, isNot(contains("'ageCategories'")));
    });

    test('l’ecran cable le poste au serveur et le reste sur la page', () {
      final screen = File('lib/screens/offre_screen.dart').readAsStringSync();
      final controller = File(
        'lib/controller/offre_controller.dart',
      ).readAsStringSync();

      expect(controller, contains('void setPositionFilter('));
      expect(screen, contains('offreController.setPositionFilter('));

      // Les deux autres criteres se posent la ou les filtres de cet ecran
      // vivent deja.
      expect(screen, contains('o.ageCategories.contains(_selectedCategory)'));
      expect(screen, contains('o.clubLevel == _selectedLevel'));

      // Reinitialiser doit repartir jusqu'au serveur : sinon le fil reste
      // filtre par un poste que plus aucun menu n'affiche.
      expect(
        screen,
        contains('offreController.setPositionFilter(const <FootballPosition>[])'),
      );

      // Un fil vide sous filtre serveur reste un fil filtre : la barre doit
      // rester a l'ecran, sinon l'utilisateur n'a aucun moyen de revenir.
      expect(screen, contains('final hasServerFilter = _selectedPosition != null;'));
      expect(screen, contains('if (allOffres.isEmpty && !hasServerFilter)'));
    });
  });

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
      // Le poste est obligatoire a la publication. Le fil filtre
      // `positionCodes` en `arrayContainsAny` cote serveur : une offre
      // publiee sans poste n'apparait dans aucune recherche par poste, et son
      // auteur n'a aucun moyen de le constater. Le controle passe par un
      // `FormField`, donc par le meme `validate()` que le titre, et l'erreur
      // se pose sous les puces plutot que dans un message general.
      expect(form, contains('FormField<List<FootballPosition>>('));
      expect(form, contains('validator: _validatePositions'));
      expect(form, contains('state.didChange(_positionCodes)'));
      expect(form, contains('String? _validatePositions('));
      expect(form, contains('Postes recherchés *'));
      expect(form, contains('maxLength: _maxTitleLength'));
      expect(form, contains('maxLength: _maxDescriptionLength'));
      expect(form, contains('bool get _hasUnsavedChanges'));
      expect(form, contains('bool _isSubmitting = false;'));
      expect(form, contains('bool _hasCompletedSubmit = false;'));
      expect(form, contains('bool get _submitLocked'));
      expect(form, contains('onPressed: _submitLocked ? null : _submitForm'));
      expect(
        form,
        contains("id: isEditing ? editingOffre!.id : _draftOfferId"),
      );
      expect(
        form,
        contains('_navigateAfterSuccessfulSubmit(response.message)'),
      );
      expect(form, contains('AdFeedback.dismissCurrent();'));
      expect(form, contains('Get.back(result: result);'));
      expect(form, isNot(contains('Get.back(result: true);')));
      expect(form, contains('Get.offAllNamed('));
      expect(form, contains('AppRoutes.main'));
      expect(form, contains("'tab': 1"));
      expect(form, contains('_resolveInitialDate('));
      expect(form, contains("locale: const Locale('fr', 'FR')"));
      expect(form, contains("DateFormat('dd MMM yyyy', 'fr_FR')"));
      expect(form, isNot(contains('_pieceJointeController')));
      expect(form, isNot(contains('Lien document')));
      expect(form, contains('pieceJointeUrl: null'));
    });

    test(
      'offre screen reacts to action responses for status, apply and delete',
      () {
        final screen = File('lib/screens/offre_screen.dart').readAsStringSync();
        final widgets = File(
          'lib/screens/offre_screen_widgets.dart',
        ).readAsStringSync();

        expect(screen, contains('await _runOfferAction('));
        expect(screen, contains('offreController.changerStatut('));
        expect(screen, contains('offreController.postulerOffre('));
        expect(screen, contains('offreController.seDesinscrireOffre('));
        expect(screen, contains('offreController.supprimerOffre('));
        expect(screen, contains('_handleActionResponse('));
        expect(screen, contains('_showSystemNotice('));
        expect(
          screen,
          contains("import 'package:adfoot/widgets/ad_system_notice.dart';"),
        );
        expect(screen, contains('AdSystemNotice('));
        expect(screen, isNot(contains('class _OfferSystemNotice')));
        expect(screen, isNot(contains('_buildOffersOverview(')));
        expect(screen, contains('_openCreateOfferForm()'));
        expect(screen, contains('_openEditOfferForm(Offre offre)'));
        expect(screen, contains('offreController.hasMoreOffres'));
        expect(screen, contains('offreController.isLoadingMore'));
        expect(screen, contains('_buildLoadMoreFooter()'));
        expect(screen, contains('offreController.loadMoreOffres()'));
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
        expect(screen, contains('Créer une offre'));
        expect(screen, contains("hintText: 'Rechercher une offre...'"));
        expect(
          screen,
          contains('constraints: const BoxConstraints(maxWidth: 760)'),
        );
        expect(widgets, contains('MaterialTapTargetSize.shrinkWrap'));
        expect(widgets, contains('VisualDensity.compact'));
        expect(widgets, contains('labelPadding: const EdgeInsets.symmetric'));
        expect(widgets, isNot(contains('class _OfferMetric')));
        expect(
          screen,
          isNot(contains('response.showToast(includeSuccess: true);')),
        );
        expect(screen, isNot(contains('AdFeedback.success(')));
        expect(screen, contains('response.message'));
        expect(screen, contains('ContactContext.offer('));
        expect(screen, contains('startGuidedConversation('));
        expect(screen, contains('findExistingConversationId('));
        expect(screen, contains('filteredOut: true'));
        expect(screen, contains('_resetFilters()'));
        expect(screen, contains("arguments: {'tab': 0}"));
      },
    );

    test('system notice is shared outside the offer screen', () {
      final notice = File(
        'lib/widgets/ad_system_notice.dart',
      ).readAsStringSync();

      expect(notice, contains('enum AdSystemNoticeTone'));
      expect(notice, contains('class AdSystemNoticeData'));
      expect(notice, contains('class AdSystemNotice extends StatelessWidget'));
      expect(notice, contains('AdSystemNoticeTone.success'));
      expect(notice, contains('AdSystemNoticeTone.info'));
      expect(notice, contains('AdSystemNoticeTone.warning'));
      expect(notice, contains('AdSystemNoticeTone.error'));
    });

    test('offre controller mutations return explicit action responses', () {
      final controller = File(
        'lib/controller/offre_controller.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/services/offers/offer_repository.dart',
      ).readAsStringSync();

      expect(controller, contains('Future<ActionResponse> publierOffre'));
      expect(controller, contains('Future<ActionResponse> modifierOffre'));
      expect(controller, contains('Future<ActionResponse> changerStatut'));
      expect(controller, contains('Future<ActionResponse> supprimerOffre'));
      expect(controller, contains('Future<ActionResponse> postulerOffre'));
      expect(controller, contains('Future<ActionResponse> seDesinscrireOffre'));
      expect(controller, contains('_offerRepository.publishOffer'));
      expect(controller, contains('_offerRepository.updateOffer'));
      expect(controller, contains('_offerRepository.applyToOffer'));
      expect(controller, contains('_offerRepository.withdrawFromOffer'));
      expect(controller, contains('StreamSubscription<OfferLiveBatch>'));
      expect(controller, contains('Future<void> loadMoreOffres()'));
      expect(controller, contains('_lastCursor'));
      expect(controller, contains('_offerPageSize'));
      expect(controller, contains('_replaceLocalOffer(offre)'));
      expect(controller, contains('_removeLocalOffer(offreId)'));
      expect(controller, contains('_setLocalOfferCandidateState'));
      expect(controller, contains('_restoreLocalOfferCandidates'));
      expect(controller, contains('previousCandidates'));
      expect(controller, contains("e.code == 'already_applied'"));
      expect(controller, contains("e.code == 'not_applied'"));
      expect(controller, contains('fetchOffersPage('));
      expect(controller, isNot(contains('runTransaction')));
      expect(repository, contains('runTransaction'));
      expect(repository, contains('class OfferFeedCursor'));
      expect(repository, contains('class OfferQueryFilter'));
      expect(repository, contains('Stream<OfferLiveBatch> watchOffers'));
      expect(repository, contains('Future<OfferFeedPage> fetchOffersPage'));
      expect(
        repository,
        contains(".orderBy('dateCreation', descending: true)"),
      );
      expect(repository, contains('.limit(limit)'));
      expect(repository, contains('startAfterDocument'));
      expect(repository, contains("'statut'"));
      expect(repository, contains("'dateFin'"));
      expect(repository, contains('_extractCandidateMaps'));
      expect(repository, contains("payload.remove('pieceJointeUrl')"));
      expect(
        repository,
        contains("payload['pieceJointeUrl'] = FieldValue.delete()"),
      );
    });

    test('offre controller keeps the mobile stream bounded and tolerant', () {
      final controller = File(
        'lib/controller/offre_controller.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/services/offers/offer_repository.dart',
      ).readAsStringSync();

      expect(controller, contains('_offerRepository'));
      expect(controller, contains('.watchOffers(limit: _offerPageSize'));
      expect(repository, contains("collection('offres')"));
      expect(repository, contains('_parseSnapshotDocs(snapshot.docs)'));

      // Tolerance is the point: one malformed document must cost its own
      // offer, not the whole batch. Asserted on the shape rather than on the
      // message, which used to be a French string logged through
      // `developer.log` -- a sink that never leaves the device, so a
      // disappearing offer left no record anywhere. It is now reported at
      // `warning`, sampled, so a permanently bad document cannot flood.
      expect(repository, contains('} catch (error, stackTrace) {'));
      expect(repository, contains("source: 'offers/parse'"));
      expect(repository, contains('AppLogger.warning('));
      expect(
        repository,
        contains(
          'fetched.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));',
        ),
      );
    });

    test('offre indexes support ordered and filtered production queries', () {
      final indexes = File('firestore.indexes.json').readAsStringSync();

      expect(indexes, contains('"collectionGroup": "offres"'));
      expect(indexes, contains('"fieldPath": "statut"'));
      expect(indexes, contains('"fieldPath": "dateFin"'));
      expect(indexes, contains('"fieldPath": "dateCreation"'));
      expect(indexes, contains('"order": "DESCENDING"'));
    });
  });
}
