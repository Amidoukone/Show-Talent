import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un flux Firestore mort doit se rebrancher, pas attendre le jeton suivant.
///
/// Une souscription `snapshots()` ne delivre plus rien apres une erreur. Les
/// controleurs de ce depot l'avaient compris et relachent leur handle dans
/// `onError`, pour qu'un appel ulterieur puisse rebrancher. Mais le seul appel
/// ulterieur etait `idTokenChanges`, c'est-a-dire la rotation horaire du
/// jeton : l'onglet restait vide jusqu'a une heure.
///
/// La production l'a montre sur les evenements : deux `permission-denied` a
/// 0,8 s d'intervalle, 89 secondes apres la creation du compte, sur un document
/// dont `authDisabled` vaut `false`. Ce n'etait pas un refus d'acces mais une
/// course -- l'ecouteur s'ouvrait avant que le jeton d'identification ait
/// atteint le canal Firestore.
///
/// Ce test tient les deux moities de l'invariant : relacher le handle, **et**
/// reprogrammer un rebranchement borne.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('EventController rebranche son flux', () {
    late String source;

    setUpAll(() {
      source = read('lib/controller/event_controller.dart');
    });

    test('le handle mort est relache', () {
      expect(
        source,
        contains('_eventsSub = null;'),
        reason: 'sans cela `fetchEvents` sort en avance pour toujours et '
            'aucun rebranchement n\'est possible',
      );
    });

    test('un rebranchement borne est reprogramme', () {
      expect(source, contains('Future<void> _scheduleRebind() async {'));
      expect(source, contains('unawaited(_scheduleRebind());'));
      expect(source, contains('static const int _rebindAttempts = 3;'));
    });

    test('le rebranchement est serialise contre une session qui change', () {
      final start = source.indexOf('Future<void> _scheduleRebind() async {');
      expect(start, isNonNegative);
      final body = source.substring(start, start + 900);

      expect(
        body,
        contains('final serial = ++_rebindSerial;'),
        reason: 'une tentative tardive ne doit pas reinstaller un flux pour '
            'une session qui a change entre-temps',
      );
      expect(body, contains('if (serial != _rebindSerial) return;'));
      expect(
        body,
        contains('if (_authSessionService.currentUser == null) return;'),
        reason: 'ne pas rebrancher apres une deconnexion',
      );
      expect(
        body,
        contains('if (_eventsSub != null) return;'),
        reason: 'quelqu\'un a deja rebranche : ne pas ouvrir un second flux',
      );
    });

    test('un retrait d\'acces reel n\'est pas reessaye en boucle', () {
      final start = source.indexOf('onError: (Object error) {');
      expect(start, isNonNegative);
      final handler = source.substring(start, source.indexOf('_scheduleRebind'));

      // La branche du refus veritable sort avant d'atteindre le
      // rebranchement : `_handleProtectedAccessDenied` possede ce cas.
      expect(handler, contains('unawaited(_handleProtectedAccessDenied());'));
      final denied = handler.indexOf('unawaited(_handleProtectedAccessDenied());');
      expect(
        handler.indexOf('return;', denied),
        greaterThan(denied),
        reason: 'sans ce `return`, un acces retire serait reessaye trois fois '
            'et rouvrirait trois fois la meme alerte',
      );
    });
  });

  // Meme forme, meme manque : ces deux flux relachent leur handle mais
  // n'ont pas de rebranchement. Documente ici pour que la dette soit visible
  // plutot que de se redecouvrir dans les journaux de production.
  group('la meme dette, ailleurs', () {
    const pending = <String, String>{
      'lib/controller/chat_controller.dart': 'chat/conversation_watch',
      'lib/controller/offre_controller.dart': 'offres/watch',
    };

    test('les flux encore sans rebranchement sont nommes', () {
      for (final entry in pending.entries) {
        final source = read(entry.key);
        expect(
          source,
          contains('onError:'),
          reason: '${entry.key} doit au moins signaler son echec',
        );
        // Si l'un des deux gagne un rebranchement, retirer la ligne de
        // `pending` et lui ajouter un groupe comme celui ci-dessus.
        expect(
          source.contains('_scheduleRebind'),
          isFalse,
          reason: '${entry.key} (${entry.value}) a maintenant un '
              'rebranchement : sortez-le de la liste de dette et tenez-le '
              'avec les memes assertions que EventController',
        );
      }
    });
  });
}
