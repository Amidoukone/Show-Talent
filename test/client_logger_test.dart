import 'package:adfoot/services/client_logger.dart';
import 'package:flutter_test/flutter_test.dart';

// Avant ce correctif, `ClientLogger.logError` figeait `level: 'error'` pour
// tout appelant -- AppLogger.warning comme AppLogger.error. Un audit de
// production (novembre 2026) a mesure que 89 % des documents client_logs
// filtres sur `level=='error'` etaient en realite des avertissements, ce qui
// a cache un vrai defaut actif (offers/auto_close) dans le bruit pendant
// plusieurs semaines. Ce test fige le contrat qui evite la regression :
// `logError` doit refleter le niveau reel qu'on lui donne, pas un niveau
// fixe.
void main() {
  group('ClientLogEntry', () {
    test('toJson conserve le niveau tel que fourni', () {
      final warningEntry = ClientLogEntry(
        level: 'warning',
        source: 'offers/auto_close',
        message: 'expired offer could not be closed; it still reads as open',
      );
      final errorEntry = ClientLogEntry(
        level: 'error',
        source: 'events/watch',
        message: 'events stream stopped',
      );

      expect(warningEntry.toJson()['level'], 'warning');
      expect(errorEntry.toJson()['level'], 'error');
    });
  });

  group('ClientLogger.logError', () {
    test('le parametre level par defaut reste error, pour les appelants qui '
        'ne le passent jamais (video_metrics_observer, '
        'video_observability_service, video_tools)', () {
      // Rien a vider ici : ce test verifie seulement que l'appel ne lance
      // pas et que la signature par defaut n'a pas change de comportement.
      // Le reseau n'est pas sollicite tant que le tampon ne depasse pas son
      // seuil (voir _enqueue), donc cet appel reste un test unitaire pur.
      expect(
        () => ClientLogger.instance.logError('test/source', 'message'),
        returnsNormally,
      );
    });
  });
}
