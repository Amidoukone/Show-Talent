/// Les pays, en codes ISO 3166-1 alpha-2.
///
/// Existe pour une raison simple : `country` était saisi en texte libre dans
/// le profil de base, et `nationalities` allait l'être aussi. « Côte d'Ivoire »,
/// « Cote dIvoire », « CIV » et « Ivory Coast » désignent le même pays et ne se
/// rencontrent jamais dans une requête — c'est le même défaut que les postes en
/// CSV, au même endroit du produit.
///
/// **Le code est stocké, le nom est affiché.** Un recruteur néerlandais et un
/// joueur ivoirien doivent trouver la même chose.
///
/// **Périmètre, et pourquoi il s'arrête là.** L'Afrique en entier, l'Europe en
/// entier, plus les nations qui recrutent ou fournissent des joueurs à ce
/// marché. Ce n'est pas la liste ISO complète : une liste de 249 entrées ferait
/// défiler l'Antarctique et les Îles Heard avant d'atteindre le Sénégal, et
/// aucun de ces pays n'a de fédération. Une entrée manquante s'ajoute ici, et
/// nulle part ailleurs.
library;

/// Nom français d'un pays, par code ISO alpha-2.
const Map<String, String> kCountryNamesFr = <String, String>{
  // Afrique
  'DZ': 'Algérie',
  'AO': 'Angola',
  'BJ': 'Bénin',
  'BW': 'Botswana',
  'BF': 'Burkina Faso',
  'BI': 'Burundi',
  'CM': 'Cameroun',
  'CV': 'Cap-Vert',
  'CF': 'Centrafrique',
  'KM': 'Comores',
  'CG': 'Congo',
  'CD': 'Congo (RDC)',
  'CI': 'Côte d’Ivoire',
  'DJ': 'Djibouti',
  'EG': 'Égypte',
  'ER': 'Érythrée',
  'SZ': 'Eswatini',
  'ET': 'Éthiopie',
  'GA': 'Gabon',
  'GM': 'Gambie',
  'GH': 'Ghana',
  'GN': 'Guinée',
  'GW': 'Guinée-Bissau',
  'GQ': 'Guinée équatoriale',
  'KE': 'Kenya',
  'LS': 'Lesotho',
  'LR': 'Liberia',
  'LY': 'Libye',
  'MG': 'Madagascar',
  'MW': 'Malawi',
  'ML': 'Mali',
  'MA': 'Maroc',
  'MU': 'Maurice',
  'MR': 'Mauritanie',
  'MZ': 'Mozambique',
  'NA': 'Namibie',
  'NE': 'Niger',
  'NG': 'Nigeria',
  'UG': 'Ouganda',
  'RW': 'Rwanda',
  'ST': 'Sao Tomé-et-Principe',
  'SN': 'Sénégal',
  'SC': 'Seychelles',
  'SL': 'Sierra Leone',
  'SO': 'Somalie',
  'SD': 'Soudan',
  'SS': 'Soudan du Sud',
  'ZA': 'Afrique du Sud',
  'TZ': 'Tanzanie',
  'TD': 'Tchad',
  'TG': 'Togo',
  'TN': 'Tunisie',
  'ZM': 'Zambie',
  'ZW': 'Zimbabwe',

  // Europe
  'AL': 'Albanie',
  'DE': 'Allemagne',
  'AD': 'Andorre',
  'AT': 'Autriche',
  'BE': 'Belgique',
  'BY': 'Biélorussie',
  'BA': 'Bosnie-Herzégovine',
  'BG': 'Bulgarie',
  'CY': 'Chypre',
  'HR': 'Croatie',
  'DK': 'Danemark',
  'ES': 'Espagne',
  'EE': 'Estonie',
  'FI': 'Finlande',
  'FR': 'France',
  'GR': 'Grèce',
  'HU': 'Hongrie',
  'IE': 'Irlande',
  'IS': 'Islande',
  'IT': 'Italie',
  'LV': 'Lettonie',
  'LI': 'Liechtenstein',
  'LT': 'Lituanie',
  'LU': 'Luxembourg',
  'MK': 'Macédoine du Nord',
  'MT': 'Malte',
  'MD': 'Moldavie',
  'MC': 'Monaco',
  'ME': 'Monténégro',
  'NO': 'Norvège',
  'NL': 'Pays-Bas',
  'PL': 'Pologne',
  'PT': 'Portugal',
  'RO': 'Roumanie',
  'GB': 'Royaume-Uni',
  'RU': 'Russie',
  'SM': 'Saint-Marin',
  'RS': 'Serbie',
  'SK': 'Slovaquie',
  'SI': 'Slovénie',
  'SE': 'Suède',
  'CH': 'Suisse',
  'CZ': 'Tchéquie',
  'TR': 'Turquie',
  'UA': 'Ukraine',

  // Nations qui recrutent ou fournissent sur ce marché
  'SA': 'Arabie saoudite',
  'AR': 'Argentine',
  'AU': 'Australie',
  'BR': 'Brésil',
  'CA': 'Canada',
  'CL': 'Chili',
  'CN': 'Chine',
  'KR': 'Corée du Sud',
  'AE': 'Émirats arabes unis',
  'US': 'États-Unis',
  'IN': 'Inde',
  'JP': 'Japon',
  'MX': 'Mexique',
  'QA': 'Qatar',
  'UY': 'Uruguay',
};

/// Vrai quand [code] est un code connu de cette liste.
bool isKnownCountryCode(Object? code) =>
    kCountryNamesFr.containsKey(normalizeCountryCode(code));

/// Ramène une saisie à un code ISO en majuscules, ou null.
///
/// N'accepte que deux lettres : un nom de pays écrit en toutes lettres est
/// précisément ce que ce fichier remplace, et le convertir ici laisserait
/// croire que le texte libre reste acceptable quelque part.
String? normalizeCountryCode(Object? raw) {
  final code = raw?.toString().trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : null;
}

/// Nom affichable d'un code, ou le code lui-même s'il est inconnu.
///
/// Ne renvoie jamais vide : un code venu d'une version plus récente doit
/// s'afficher tel quel plutôt que de laisser un trou dans la fiche.
String countryLabel(Object? raw) {
  final code = normalizeCountryCode(raw);
  if (code == null) return '';
  return kCountryNamesFr[code] ?? code;
}

/// Les pays par nom, pour un sélecteur.
List<MapEntry<String, String>> countriesByName() {
  final entries = kCountryNamesFr.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return List<MapEntry<String, String>>.unmodifiable(entries);
}
