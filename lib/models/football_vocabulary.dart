/// Le vocabulaire du football, en listes fermées.
///
/// Tout ce qu'un recruteur filtre doit vivre ici, et nulle part ailleurs. Le
/// profil avancé stockait jusqu'ici du texte libre — postes en CSV, type de
/// structure en toutes lettres, zones séparées par des virgules — et on ne
/// filtre pas du texte libre : « Défense », « défenseur central », « CB » et
/// « centre-back » désignent le même joueur et ne se rencontrent jamais dans
/// une requête.
///
/// Deux principes tiennent tout le fichier.
///
/// **Le code est stocké, le libellé est affiché.** Un club néerlandais et un
/// club ivoirien doivent trouver le même joueur ; indexer un libellé enferme
/// la base dans une langue, et le jour où l'on ajoute l'anglais il faut
/// réécrire toutes les fiches. Les codes sont ceux que lisent les recruteurs
/// (`CB`, `DM`, `ST`), pas des identifiants inventés.
///
/// **Rien ici n'est auto-déclaratif et invérifiable.** Une « qualité clé »
/// saisie par le joueur lui-même — rapide, bon dribbleur — n'a aucune valeur
/// pour un scout et décrédibilise le reste de la fiche. Ce fichier ne décrit
/// que des faits : un poste, un pied, un statut contractuel, un niveau de
/// compétition. Ce qui relève du jugement se voit sur la vidéo.
library;

/// Grande famille de postes, pour un filtre grossier.
///
/// Un recruteur commence souvent par « un défenseur », puis précise. Sans ce
/// niveau, chercher un défenseur impose de cocher `CB`, `LB` et `RB` à la
/// main.
enum PositionGroup {
  goalkeeper('GK', 'Gardien', 'Goalkeeper'),
  defender('DEF', 'Défenseur', 'Defender'),
  midfielder('MID', 'Milieu', 'Midfielder'),
  forward('FWD', 'Attaquant', 'Forward');

  const PositionGroup(this.code, this.labelFr, this.labelEn);

  final String code;
  final String labelFr;
  final String labelEn;
}

/// Poste occupé, dans le vocabulaire des recruteurs.
///
/// Dix codes, et pas trente. Ce n'est pas une simplification : c'est la
/// contrainte de `array-contains-any`, qui accepte dix valeurs au maximum
/// dans une requête Firestore. Un vocabulaire plus fin rendrait impossible la
/// requête « n'importe quel poste défensif », qui est la plus courante.
///
/// Un joueur en déclare un à trois, par ordre de préférence.
enum FootballPosition {
  goalkeeper('GK', 'Gardien', 'Goalkeeper', PositionGroup.goalkeeper),
  centreBack('CB', 'Défenseur central', 'Centre-back', PositionGroup.defender),
  leftBack('LB', 'Latéral gauche', 'Left-back', PositionGroup.defender),
  rightBack('RB', 'Latéral droit', 'Right-back', PositionGroup.defender),
  defensiveMidfielder(
    'DM',
    'Milieu défensif',
    'Defensive midfielder',
    PositionGroup.midfielder,
  ),
  centralMidfielder(
    'CM',
    'Milieu central',
    'Central midfielder',
    PositionGroup.midfielder,
  ),
  attackingMidfielder(
    'AM',
    'Milieu offensif',
    'Attacking midfielder',
    PositionGroup.midfielder,
  ),
  leftWinger('LW', 'Ailier gauche', 'Left winger', PositionGroup.forward),
  rightWinger('RW', 'Ailier droit', 'Right winger', PositionGroup.forward),
  striker('ST', 'Attaquant', 'Striker', PositionGroup.forward);

  const FootballPosition(this.code, this.labelFr, this.labelEn, this.group);

  final String code;
  final String labelFr;
  final String labelEn;
  final PositionGroup group;

  /// Le maximum qu'un joueur peut déclarer.
  ///
  /// Un joueur qui coche huit postes ne dit plus rien : il dit qu'il ne sait
  /// pas où il joue, ce qu'un recruteur lit comme un défaut et non comme une
  /// polyvalence.
  static const int maxPerPlayer = 3;

  /// Le maximum qu'une requête peut demander, impose par `array-contains-any`.
  static const int maxPerQuery = 10;
}

/// Pied fort.
enum StrongFoot {
  left('left', 'Gauche', 'Left'),
  right('right', 'Droit', 'Right'),
  both('both', 'Les deux', 'Two-footed');

  const StrongFoot(this.code, this.labelFr, this.labelEn);

  final String code;
  final String labelFr;
  final String labelEn;
}

/// Situation contractuelle.
///
/// Avec la nationalité, c'est ce qui décide si un club peut agir. Un joueur
/// libre et un joueur sous contrat jusqu'en 2028 ne sont pas la même offre,
/// et un recruteur qui découvre la différence après avoir pris contact ne
/// revient pas.
enum ContractStatus {
  free('free', 'Libre', 'Free agent'),
  underContract('under_contract', 'Sous contrat', 'Under contract'),
  onLoan('on_loan', 'En prêt', 'On loan'),

  /// Sans contrat professionnel : le cas de la très grande majorité des
  /// joueurs que cette application existe pour faire connaître.
  amateur('amateur', 'Amateur', 'Amateur');

  const ContractStatus(this.code, this.labelFr, this.labelEn);

  final String code;
  final String labelFr;
  final String labelEn;

  /// Vrai quand une date de fin de contrat a un sens.
  bool get expectsEndDate =>
      this == ContractStatus.underContract || this == ContractStatus.onLoan;
}

/// Niveau de la structure — celle du club, ou celle où évolue le joueur.
///
/// Sans lui, une statistique ne veut rien dire : douze buts en académie U17 et
/// douze buts en première division ne se lisent pas de la même façon, et une
/// fiche qui ne le précise pas oblige le recruteur à demander.
enum ClubLevel {
  professional('pro', 'Professionnel', 'Professional'),
  semiProfessional('semi_pro', 'Semi-professionnel', 'Semi-professional'),
  academy('academy', 'Académie / centre de formation', 'Academy'),
  amateur('amateur', 'Amateur', 'Amateur');

  const ClubLevel(this.code, this.labelFr, this.labelEn);

  final String code;
  final String labelFr;
  final String labelEn;
}

/// Catégorie d'âge, telle que le football la nomme.
///
/// Un club ne recrute pas « un joueur de 17 ans », il recrute « en U19 ». La
/// borne est l'âge maximum de la catégorie.
enum AgeCategory {
  u15('U15', 15),
  u17('U17', 17),
  u19('U19', 19),
  u21('U21', 21),
  senior('Senior', null);

  const AgeCategory(this.code, this.maxAge);

  final String code;

  /// Âge maximum, ou null pour les seniors.
  final int? maxAge;

  String get labelFr => code;
  String get labelEn => code;
}

/// Résout un code vers sa valeur, avec tolérance sur la casse et les espaces.
///
/// Renvoie null sur un code inconnu plutôt que de lever : un document écrit
/// par une version plus récente de l'application, ou par le portail admin, ne
/// doit jamais faire planter un profil à l'affichage. Un poste qu'on ne
/// comprend pas est un poste qu'on n'affiche pas, pas un écran blanc.
T? codeToValue<T extends Enum>(
  List<T> values,
  String Function(T) codeOf,
  Object? raw,
) {
  final normalized = raw?.toString().trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;

  for (final value in values) {
    if (codeOf(value).toLowerCase() == normalized) return value;
  }
  return null;
}

/// Les résolveurs, un par vocabulaire.
///
/// Regroupés ici pour que l'appelant n'ait pas à connaître [codeToValue] ni à
/// répéter la liste des valeurs — répétition qui finit toujours par oublier
/// une entrée ajoutée depuis.
abstract final class FootballVocabulary {
  static FootballPosition? position(Object? raw) =>
      codeToValue(FootballPosition.values, (value) => value.code, raw);

  static StrongFoot? strongFoot(Object? raw) =>
      codeToValue(StrongFoot.values, (value) => value.code, raw);

  static ContractStatus? contractStatus(Object? raw) =>
      codeToValue(ContractStatus.values, (value) => value.code, raw);

  static ClubLevel? clubLevel(Object? raw) =>
      codeToValue(ClubLevel.values, (value) => value.code, raw);

  static AgeCategory? ageCategory(Object? raw) =>
      codeToValue(AgeCategory.values, (value) => value.code, raw);

  /// Les postes d'un document, dans l'ordre déclaré, sans doublon ni inconnu.
  ///
  /// Tronque à [FootballPosition.maxPerPlayer] : une fiche qui en porterait
  /// plus vient forcément d'une écriture qui a contourné le formulaire, et
  /// l'afficher entièrement laisserait croire que la limite n'existe pas.
  static List<FootballPosition> positions(Object? raw) {
    if (raw is! List) return const <FootballPosition>[];

    final resolved = <FootballPosition>[];
    for (final entry in raw) {
      final parsed = position(entry);
      if (parsed == null || resolved.contains(parsed)) continue;
      resolved.add(parsed);
      if (resolved.length == FootballPosition.maxPerPlayer) break;
    }
    return List<FootballPosition>.unmodifiable(resolved);
  }
}
