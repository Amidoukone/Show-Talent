/// Le plafond de vidéos publiées d'un compte joueur, côté application.
///
/// L'autorité reste le serveur : `MAX_PUBLIC_PLAYER_VIDEOS` dans
/// `functions/src/upload_session.ts`, vérifié dans la même transaction que la
/// création du document vidéo, donc à l'abri des courses. Cette constante ne
/// remplace pas ce contrôle, elle sert à ne pas faire travailler
/// l'utilisateur pour rien.
///
/// Sans elle, un joueur au plafond choisissait sa vidéo, attendait le
/// découpage, la génération de miniature et le début du téléversement, puis
/// recevait « Vous avez deja 10 videos publiques » — la trace exacte relevée
/// dans `client_logs` d'adfoot-production le 2026-08-22 à 09:17:34 puis, le
/// temps d'un nouvel essai, à 09:17:52. Le compte concerné détenait bien
/// exactement dix vidéos `ready`.
///
/// Les deux valeurs sont épinglées ensemble par
/// `test/video_publication_quota_guardrails_test.dart` : elles doivent
/// bouger ensemble ou pas du tout.
class VideoPublicationQuota {
  VideoPublicationQuota._();

  static const int maxPublishedVideos = 10;
}

/// Ce que la vérification préalable a pu établir.
enum VideoPublicationQuotaState {
  /// Il reste de la place sous le plafond.
  allowed,

  /// Le plafond est atteint : inutile de commencer un téléversement.
  exhausted,

  /// Rien n'a pu être établi (session absente, lecture Firestore en échec).
  ///
  /// Volontairement distinct de [exhausted] : une lecture ratée n'est pas un
  /// refus, et bloquer dessus interdirait de publier à cause d'un réseau
  /// capricieux. Le serveur tranchera.
  unknown,
}
