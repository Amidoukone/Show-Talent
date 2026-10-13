import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Deux comportements nominaux étaient comptés comme des pannes, et ils
/// occupaient à eux seuls 42 % du canal de diagnostic.
///
/// Relevé réel du 13 octobre, sur les 200 dernières entrées de `client_logs` :
/// 80 `PERMISSION_DENIED` de la fermeture automatique d'événements, et des
/// `play_error — Video init cancelled: context_disposed` à chaque balayage du
/// fil. Aucun des deux ne décrit un défaut ; les deux noient ceux qui en sont.
///
/// Ce n'était pas seulement du bruit. L'échantillonnage des avertissements est
/// passé à 100 % pour la phase d'appareils (`CLIENT_LOG_WARNING_SAMPLE_PERCENT`),
/// donc ce qui était dilué cinq fois sur six arrive désormais entier — dans le
/// canal dont la panne des notifications iOS vient de prouver qu'on dépend.
void main() {
  group('la fermeture automatique n\'écrit que chez son organisateur', () {
    final controller = _read('lib/controller/event_controller.dart');

    test('elle est conditionnée au propriétaire', () {
      final prepare = controller.indexOf('List<Event> _prepareEvents(');
      expect(prepare, isNonNegative);
      final body = controller.substring(
        prepare,
        (prepare + 2600).clamp(prepare, controller.length),
      );

      final guard = body.indexOf('event.organisateur.uid == currentUid');
      final write = body.indexOf('updateEventStatus(');
      expect(
        guard,
        isNonNegative,
        reason: 'firestore.rules ne laisse changer `statut` qu\'a '
            'l\'organisateur ; sans ce test, chaque lecteur tentait de fermer '
            'les evenements expires de tout le monde, a chaque snapshot',
      );
      expect(
        guard,
        lessThan(write),
        reason: 'le test doit preceder l\'ecriture, pas la suivre',
      );
    });

    test('l\'affichage local reste corrigé pour tout le monde', () {
      // La seule partie qui concernait le lecteur : un evenement dont la date
      // est passee se lit « ferme » a l'ecran, que le serveur l'ait enregistre
      // ou non. Le garde ne doit pas avoir emporte ca avec lui.
      final prepare = controller.indexOf('List<Event> _prepareEvents(');
      final body = controller.substring(
        prepare,
        (prepare + 2600).clamp(prepare, controller.length),
      );

      final guard = body.indexOf('event.organisateur.uid == currentUid');
      final localWrite = body.indexOf("event.statut = 'ferme';", guard);
      final closingBrace = body.indexOf('updatedEvents.add(event);');
      expect(localWrite, isNonNegative);
      expect(
        localWrite,
        lessThan(closingBrace),
        reason: 'la correction d\'affichage doit rester hors du garde',
      );
    });
  });

  group('une annulation de défilement n\'est pas une panne de lecture', () {
    test('le type d\'annulation est public, donc distinguable', () {
      // Dans le domaine, pas dans le gestionnaire : c'est un concept de
      // lecture, et video_architecture_test tient a ce que le
      // gestionnaire ne garde qu'un seul travail.
      expect(
        _read('lib/videos/domain/video_init_cancelled.dart'),
        contains('class VideoInitCancelled implements Exception'),
        reason: 'prive, il etait indistinguable d\'un vrai echec depuis '
            'le widget qui rapporte',
      );
      expect(
        _read('lib/videos/video_manager.dart'),
        isNot(contains('class VideoInitCancelled')),
        reason: 'le gestionnaire l\'utilise, il ne le declare plus',
      );
    });

    test('le lecteur l\'attrape avant de rapporter une erreur', () {
      final player = _read('lib/widgets/smart_video_player.dart');
      final cancelled = player.indexOf('} on VideoInitCancelled catch');
      expect(cancelled, isNonNegative);

      // L'ordre compte : `on VideoInitCancelled` doit preceder le `catch`
      // generique, sinon il n'est jamais atteint.
      final generic = player.indexOf('} catch (e, st) {', cancelled);
      expect(generic, greaterThan(cancelled));

      // Et il ne doit rien envoyer a client_logs.
      expect(
        player.substring(cancelled, generic),
        isNot(contains('logPlaybackError')),
      );
    });
  });
}
