import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/utils/country_codes.dart';

/// Ce qu'un club déclare de lui-même, typé.
///
/// Remplace `clubProfile`, qui portait `structureType` en toutes lettres et
/// `categories` en CSV — donc deux champs sur lesquels aucune recherche n'était
/// possible, dans un produit dont c'est la raison d'être.
///
/// Stocké à plat sur `users/{uid}`, comme [PlayerFootballProfile] et pour la
/// même raison : une requête Firestore n'indexe pas utilement un champ enfoui
/// dans une map.
///
/// **Les besoins de recrutement ont disparu d'ici.** Ils vivaient dans
/// `clubProfile.needs`, saisis en texte et affichés sur la fiche, pendant que
/// les offres publiées par le même club portaient déjà la même information.
/// Deux sources pour un seul fait finissent toujours par se contredire, et
/// c'est l'offre qui est datée, modérée et candidatable — c'est donc elle qui
/// fait foi.
class ClubFootballProfile {
  const ClubFootballProfile({
    this.level,
    this.ageCategories = const <AgeCategory>[],
    this.federationId,
  });

  /// Niveau de la structure : professionnel, semi-pro, académie, amateur.
  final ClubLevel? level;

  /// Catégories réellement engagées.
  final List<AgeCategory> ageCategories;

  /// Numéro d'affiliation à la fédération.
  ///
  /// C'est le champ qui rend un club vérifiable. Un club qui n'en donne pas
  /// n'est pas forcément faux, mais rien ne permet de le confirmer — et c'est
  /// exactement ce que l'administration doit contrôler avant d'accorder le
  /// badge « Vérifié par Adfoot ».
  final String? federationId;

  bool get isEmpty =>
      level == null && ageCategories.isEmpty && federationId == null;

  bool get isNotEmpty => !isEmpty;

  factory ClubFootballProfile.fromUserMap(Map<String, dynamic> map) {
    return ClubFootballProfile(
      level: FootballVocabulary.clubLevel(map['clubLevel']),
      ageCategories: FootballVocabulary.ageCategories(
        map['clubAgeCategories'],
      ),
      federationId: _text(map['clubFederationId']),
    );
  }

  Map<String, dynamic> toPatch() {
    return <String, dynamic>{
      'clubLevel': level?.code,
      'clubAgeCategories': ageCategories.map((c) => c.code).toList(),
      'clubFederationId': federationId,
    };
  }

  static List<String> get writableFieldPaths => <String>[
    'clubLevel',
    'clubAgeCategories',
    'clubFederationId',
  ];
}

/// Ce qu'un agent ou un recruteur déclare de lui-même, typé.
///
/// Remplace `agentProfile`, dont `licenseCountry` était du texte libre et
/// `zones` un CSV.
class AgentFootballProfile {
  const AgentFootballProfile({
    this.licenceNumber,
    this.licenceCountry,
    this.countries = const <String>[],
  });

  /// Numéro de licence d'agent.
  ///
  /// Le seul champ de tout ce modèle qui soit **vérifiable publiquement** :
  /// les fédérations publient les registres de leurs agents licenciés. C'est
  /// donc lui qui sépare un agent réel d'un compte qui s'en réclame, et la
  /// crédibilité de la plateforme auprès des joueurs en dépend plus que de
  /// n'importe quel autre champ.
  final String? licenceNumber;

  /// Fédération émettrice, en code ISO — sans quoi un numéro de licence ne
  /// peut être confronté à aucun registre.
  final String? licenceCountry;

  /// Pays d'intervention, en codes ISO.
  ///
  /// Remplace `zones`, où l'on écrivait « Europe, Afrique » : deux continents
  /// ne se croisent avec aucune recherche de joueur, qui raisonne par pays.
  final List<String> countries;

  /// Au-delà, la donnée cesse d'être une zone d'intervention pour devenir une
  /// liste, et une liste ne se filtre plus utilement.
  static const int maxCountries = 10;

  bool get isEmpty =>
      licenceNumber == null && licenceCountry == null && countries.isEmpty;

  bool get isNotEmpty => !isEmpty;

  factory AgentFootballProfile.fromUserMap(Map<String, dynamic> map) {
    return AgentFootballProfile(
      licenceNumber: _text(map['agentLicenceNumber']),
      licenceCountry: normalizeCountryCode(map['agentLicenceCountry']),
      countries: _countryCodes(map['agentCountries']),
    );
  }

  Map<String, dynamic> toPatch() {
    return <String, dynamic>{
      'agentLicenceNumber': licenceNumber,
      'agentLicenceCountry': licenceCountry,
      'agentCountries': countries,
    };
  }

  static List<String> get writableFieldPaths => <String>[
    'agentLicenceNumber',
    'agentLicenceCountry',
    'agentCountries',
  ];
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// Codes ISO en majuscules, sans doublon ni inconnu.
///
/// Un nom de pays écrit en toutes lettres est refusé : c'est précisément ce
/// que ce modèle remplace, et l'accepter ici rouvrirait la porte au texte
/// libre par le bas.
List<String> _countryCodes(Object? value) {
  if (value is! List) return const <String>[];

  final codes = <String>[];
  for (final entry in value) {
    final code = normalizeCountryCode(entry);
    if (code == null || codes.contains(code)) continue;
    codes.add(code);
    if (codes.length == AgentFootballProfile.maxCountries) break;
  }
  return List<String>.unmodifiable(codes);
}
