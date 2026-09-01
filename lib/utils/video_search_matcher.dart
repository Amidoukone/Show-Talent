import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';

const Map<String, List<String>> _positionSynonyms = {
  'attaquant': [
    'attaque',
    'attaquant',
    'buteur',
    'avant',
    'avant centre',
    'ailier',
    'ailier droit',
    'ailier gauche',
    'offensif',
    'forward',
    'striker',
  ],
  'defenseur': [
    'defense',
    'defenseur',
    'defenseure',
    'central',
    'defenseur central',
    'arriere',
    'arriere droit',
    'arriere gauche',
    'lateral',
    'lateral droit',
    'lateral gauche',
    'stoppeur',
    'cb',
    'rb',
    'lb',
  ],
  'milieu': [
    'milieu',
    'relayeur',
    'sentinelle',
    'recuperateur',
    'meneur',
    'meneur de jeu',
    'milieu defensif',
    'milieu relayeur',
    'milieu offensif',
    'mdf',
    'moc',
    'box to box',
  ],
  'gardien': [
    'gardien',
    'gardienne',
    'goal',
    'goalkeeper',
    'portier',
    'gardien de but',
  ],
};

String normalizeVideoSearchText(String value) {
  var normalized = value.toLowerCase().trim();
  const replacements = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };

  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }

  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Set<String> expandVideoSearchQuery(String query) {
  final normalizedQuery = normalizeVideoSearchText(query);
  if (normalizedQuery.isEmpty) {
    return const <String>{};
  }

  final terms = <String>{normalizedQuery};
  final tokens = normalizedQuery
      .split(' ')
      .where((token) => token.length >= 2 || RegExp(r'^\d+$').hasMatch(token));
  terms.addAll(tokens);

  final snapshot = terms.toList(growable: false);
  for (final term in snapshot) {
    for (final aliases in _positionSynonyms.values) {
      final normalizedAliases = aliases.map(normalizeVideoSearchText).toSet();
      if (normalizedAliases.contains(term)) {
        terms.addAll(normalizedAliases);
      }
    }
  }

  return terms.where((term) => term.isNotEmpty).toSet();
}

bool matchesVideoSearch(Video video, AppUser? author, String query) {
  final terms = expandVideoSearchQuery(query);
  if (terms.isEmpty) {
    return false;
  }

  final videoHaystack = normalizeVideoSearchText(
    [
      video.description,
      video.caption,
    ].whereType<String>().join(' '),
  );

  if (_containsAnySearchTerm(videoHaystack, terms)) {
    return true;
  }

  return author != null && matchesUserVideoSearch(author, query);
}

bool matchesUserVideoSearch(AppUser user, String query) {
  final terms = expandVideoSearchQuery(query);
  if (terms.isEmpty) {
    return false;
  }

  final haystack = normalizeVideoSearchText(_userSearchValues(user).join(' '));
  return _containsAnySearchTerm(haystack, terms);
}

Iterable<String> _userSearchValues(AppUser user) sync* {
  yield user.nom;
  yield user.role;
  // Les postes types, en toutes lettres : c'est « Milieu axial » que
  // l'utilisateur tape dans la recherche, pas « CM ». Le code seul ne
  // repondrait a personne.
  for (final position in user.football.positions) {
    yield position.labelFr;
  }
  // Le poste en texte libre ne subsiste que pour le coach ; pour un joueur il
  // n'est plus ecrit, et le laisser ici ferait remonter un ancien poste
  // longtemps apres qu'il a change.
  if (user.isCoach && user.position != null) yield user.position!;

  final club = user.football.currentClubName ?? user.team ?? user.clubActuel;
  if (club != null) yield club;

  if (user.bio != null) yield user.bio!;
  if (user.city != null) yield user.city!;
  if (user.region != null) yield user.region!;
  if (user.country != null) yield user.country!;

  final profile = user.playerProfile;
  if (profile != null) {
    yield* _deepStringValues(profile);
  }
}

Iterable<String> _deepStringValues(dynamic value) sync* {
  if (value is String) {
    yield value;
    return;
  }

  if (value is Iterable) {
    for (final item in value) {
      yield* _deepStringValues(item);
    }
    return;
  }

  if (value is Map) {
    for (final item in value.values) {
      yield* _deepStringValues(item);
    }
  }
}

bool _containsAnySearchTerm(String haystack, Set<String> terms) {
  if (haystack.isEmpty) {
    return false;
  }

  for (final term in terms) {
    if (haystack.contains(term)) {
      return true;
    }
  }
  return false;
}
