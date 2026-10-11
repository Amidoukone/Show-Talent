import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un document absent est une reponse, pas un refus.
///
/// Firestore evalue bien la regle d'un `get` sur un document inexistant, mais
/// `resource` y est null : toute regle qui atteint `resource.data` refuse cette
/// lecture au lieu d'y repondre « introuvable ». Le client, lui, voit un
/// `permission-denied` la ou il attendait un `doc.exists == false`.
///
/// Ce qui s'est passe en production : `BlockRepository.isBlockedEitherWay` lit
/// les deux ids directionnels de blocage avant chaque ouverture de conversation
/// et chaque envoi, et dans la quasi-totalite des cas aucun des deux documents
/// n'existe. La regle `blocks` lisait `resource.data.blockerUid`. Plus un seul
/// message ne partait de l'application, avec pour seul symptome un
/// « impossible de demarrer la conversation » qui ne nommait rien.
///
/// Les tests emulateur de `test/rules/firestore-rules.test.mjs` couvrent
/// desormais le comportement ; ils exigent Java 21. Ces assertions-ci portent
/// sur le *texte* des regles et tournent dans `flutter test`, donc partout.
/// Les deux sont necessaires, pour la meme raison qu'ailleurs dans ce depot :
/// une regle dont la formulation parait juste et dont l'evaluation ne l'est
/// pas.
void main() {
  group('Firestore missing-document read guardrails', () {
    late String rules;

    setUpAll(() {
      rules = File('firestore.rules').readAsStringSync();
    });

    test('un blocage inexistant est autorise par son id, pas par son contenu', () {
      expect(rules, contains('function blockIdNames(blockId, uid) {'));
      expect(
        rules,
        contains('blockIdNames(blockId, request.auth.uid)'),
        reason: "l'autorisation du cas absent doit se decider sur l'id",
      );
      // Le contenu reste la source d'autorite des que le document existe,
      // et les requetes ne renvoient jamais de document absent.
      expect(rules, contains('allow list: if signedInAndActive() &&'));
      expect(
        rules,
        contains('request.auth.uid == resource.data.blockerUid'),
        reason: 'les deux flux directionnels de BlockController',
      );
    });

    test('les lectures par id gerent le document absent', () {
      // Chaque entree : une collection que le client lit par id, et le code
      // qui traite deja le « introuvable » comme un resultat normal.
      const guardedGets = <String, String>{
        'conversations': 'ChatRepository.watchConversationById',
        'public_profiles': 'ChatRepository.canSendMessage / watchUserById',
        'contact_intakes':
            'ChatRepository._recoverMissingGuidedContactIntake',
        // `videos` garde un seul `allow read` et tranche dans
        // canReadVideo() : verifie juste en dessous.
      };

      for (final entry in guardedGets.entries) {
        final start = rules.indexOf('match /${entry.key}/{');
        expect(
          start,
          isNonNegative,
          reason: 'bloc de regles introuvable pour ${entry.key}',
        );
        final blockEnd = rules.indexOf('\n    match /', start + 1);
        final block = rules.substring(
          start,
          blockEnd == -1 ? rules.length : blockEnd,
        );

        expect(
          block,
          contains('allow get:'),
          reason:
              '${entry.key} doit scinder get/list pour traiter le document '
              'absent sans relacher les requetes (${entry.value})',
        );
      }

      // `videos` decide via canReadVideo(), pas en ligne dans le bloc :
      // HomeFeedRepository.fetchReadyVideoById resout un id venu d'un lien de
      // partage ou d'une notification, qui peut avoir ete supprime depuis.
      expect(rules, contains('function canReadVideo() {'));
      expect(rules, contains('function canReadExistingVideo() {'));
      expect(
        rules.substring(
          rules.indexOf('function canReadVideo() {'),
          rules.indexOf('function canReadExistingVideo() {'),
        ),
        contains('resource == null'),
      );
    });

    test('la protection ne depend jamais de l\'absence du document', () {
      // Le garde `resource == null` ouvre l'absence, et seulement elle : les
      // conditions de contenu doivent rester presentes a l'identique.
      expect(
        rules,
        contains('resource.data.isMinorProfile == false'),
        reason: 'la porte age des projections publiques reste en place',
      );
      expect(
        rules,
        contains(
          'conversationParticipantsCanMessage(resource.data.utilisateurIds)',
        ),
        reason: 'la lecture d\'une conversation reelle reste conditionnee',
      );
      expect(
        rules,
        contains('resource.data.requesterUid == request.auth.uid'),
        reason: 'une demande de contact reelle reste reservee a ses parties',
      );
    });

    test('le client ne depend pas du deploiement de ces regles', () {
      // Un build publie peut tourner devant des regles plus anciennes (voir
      // docs/inter-repo-admin-mobile-runbook.md, ordre de deploiement). La
      // verification de blocage est consultative : son echec ne doit jamais
      // empecher un envoi, puisque la regle d'ecriture tranche de toute facon.
      final repository = File(
        'lib/services/users/block_repository.dart',
      ).readAsStringSync();

      expect(repository, contains('Future<bool> _blockExists('));
      final start = repository.indexOf('Future<bool> _blockExists(');
      final body = repository.substring(start);
      expect(body, contains('} catch ('));
      expect(
        body.indexOf('return false;'),
        greaterThan(body.indexOf('} catch (')),
        reason:
            'une pre-verification sans reponse vaut « rien de connu contre », '
            'pas « envoi impossible »',
      );

      // Et les trois appelants mappent l'echec au lieu de le laisser fuir
      // vers le `catch` generique des ecrans.
      final controller = File(
        'lib/controller/chat_controller.dart',
      ).readAsStringSync();
      expect(
        controller.contains('} on ChatFlowException {'),
        isTrue,
        reason: 'un message deja lisible ne doit pas etre re-etiquete',
      );
    });
  });
}
