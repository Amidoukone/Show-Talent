import 'dart:collection';

/// Où chaque vidéo en était quand son lecteur a signalé pour la dernière fois.
///
/// **Pourquoi cette mémoire existe.** Quitter Accueil détruit tout le contexte
/// vidéo : `MainScreen` échange le corps de ses onglets au lieu de les garder
/// dans un `IndexedStack`, donc le pager part avec l'écran et emporte chaque
/// contrôleur, y compris celui à l'écran. Revenir reconstruit un lecteur sur
/// la même vidéo, à l'index que le contrôleur permanent a conservé, et
/// jusqu'ici à 0:00. Une vidéo entamée depuis vingt secondes recommençait,
/// ce qui se lit comme un rechargement même quand aucun octet n'a bougé.
///
/// **Ce qu'elle ne résout pas.** Rien du coût réseau. Une vidéo diffusée en
/// flux n'atteint le disque que si l'utilisateur fait défiler au-delà, donc
/// un retour peut encore retélécharger ; reprendre au bon endroit rend
/// seulement cette attente honnête au lieu de la faire passer pour un
/// redémarrage. Voir `docs/audit-lecture-video-2026-10-17.md`.
///
/// **Durée de vie.** Volontairement plus longue que celle d'un contexte :
/// `VideoManager.disposeAllForContext` est précisément le moment que cette
/// mémoire compense, donc l'effacer là reviendrait à perdre la réponse à
/// l'instant exact où la question se pose. Elle est bornée à la place.
class ResumePositionStore {
  /// Assez d'entrées pour couvrir une longue session de fil, assez peu pour
  /// rester gratuite : chacune est une courte chaîne et une [Duration].
  static const int maxEntries = 64;

  /// En dessous, reprendre et redémarrer reviennent au même, et le `seekTo`
  /// ne coûterait qu'un aller-retour pour rien.
  static const Duration minPosition = Duration(seconds: 3);

  /// Aussi près de la fin, le spectateur a terminé. Le ramener à 0:28 d'un
  /// clip de 0:30 est pire que de le laisser rejouer.
  static const Duration endMargin = Duration(seconds: 5);

  final LinkedHashMap<String, Duration> _positions =
      LinkedHashMap<String, Duration>();

  int get length => _positions.length;

  /// Clé sur l'URL d'origine, pas sur l'URL résolue. Le rendu peut changer
  /// d'une visite à l'autre, un retour sur connexion lente résolvant en 480p
  /// là où la première fois servait du 1080p, et la position appartient à la
  /// vidéo, pas au fichier qui l'a servie.
  String _key(String contextKey, String url) => '$contextKey|${url.trim()}';

  /// Enregistre où [url] en est.
  ///
  /// Hors des bornes, l'entrée est **retirée** plutôt qu'ignorée : une vidéo
  /// regardée jusqu'au bout après avoir été reprise ne doit pas conserver la
  /// position d'avant, sinon la fois suivante repartirait du milieu.
  void remember(
    String contextKey,
    String url, {
    required Duration position,
    required Duration duration,
  }) {
    final key = _key(contextKey, url);

    final tooEarly = position < minPosition;
    final nearlyDone =
        duration > Duration.zero && position >= duration - endMargin;
    if (tooEarly || nearlyDone) {
      _positions.remove(key);
      return;
    }

    // Retirer puis réinsérer déplace l'entrée en fin de file, donc l'éviction
    // ci-dessous sacrifie la vidéo que personne n'a touchée depuis le plus
    // longtemps plutôt qu'une au hasard.
    _positions.remove(key);
    _positions[key] = position;

    while (_positions.length > maxEntries) {
      _positions.remove(_positions.keys.first);
    }
  }

  /// Où [url] doit reprendre, ou null pour partir du début.
  Duration? positionFor(String contextKey, String url) =>
      _positions[_key(contextKey, url)];

  void forget(String contextKey, String url) {
    _positions.remove(_key(contextKey, url));
  }

  void clear() => _positions.clear();
}
