/// Une initialisation abandonnee parce que plus personne n'en attend le
/// resultat : la tuile a ete detruite, le contexte liberee, l'utilisateur a
/// fait defiler.
///
/// **Ce n'est pas un echec de lecture**, et toute la raison d'etre de ce type
/// est que l'appelant puisse le dire. Tant qu'il etait prive a
/// `video_manager.dart`, `SmartVideoPlayer` ne pouvait pas le distinguer d'une
/// vraie panne et rapportait chaque defilement comme un `play_error` en niveau
/// erreur : « Video init cancelled: context_disposed » arrivait dans
/// `client_logs` a chaque balayage du fil.
///
/// Un canal de diagnostic qui compte le comportement nominal comme une panne
/// finit par cacher celles qui en sont. Sur les 200 dernieres entrees du
/// 13 octobre 2026, ces annulations et la boucle de fermeture d'evenements
/// occupaient 42 % du releve -- dans le canal dont la panne des notifications
/// iOS venait de prouver qu'on depend.
///
/// Dans `lib/videos/domain/` et non dans le gestionnaire : c'est un concept du
/// domaine de lecture, au meme titre que le palier reseau ou la porte de
/// lecture, et `video_architecture_test` tient a ce que le gestionnaire ne
/// garde qu'un seul travail.
class VideoInitCancelled implements Exception {
  const VideoInitCancelled(this.reason);

  /// Ce qui a rendu le resultat inutile : `context_disposed`,
  /// `context_disposed_lru_hit`, `context_disposed_waiting_for_slot`...
  ///
  /// Conserve pour les traces de debogage, jamais montre a l'utilisateur.
  final String reason;

  @override
  String toString() => 'Video init cancelled: $reason';
}
