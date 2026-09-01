import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:adfoot/models/football_vocabulary.dart';
import 'package:adfoot/models/user.dart';

/// Ce qu'un recruteur demande.
///
/// Volontairement pauvre : quatre critères, ceux qu'un club pose avant de
/// regarder une vidéo. Un formulaire de recherche à quinze champs n'est pas
/// plus puissant, il est seulement plus long à remplir — et chaque critère
/// ajouté ici est un index composite de plus à déclarer et à déployer.
class TalentSearchQuery {
  const TalentSearchQuery({
    this.positions = const <FootballPosition>[],
    this.nationality,
    this.bornFrom,
    this.bornUntil,
    this.openToOpportunitiesOnly = false,
  });

  /// Postes acceptés. Vide signifie « tous ».
  final List<FootballPosition> positions;

  /// Nationalité, en code ISO alpha-2.
  final String? nationality;

  /// Bornes d'année de naissance, incluses.
  ///
  /// Un club raisonne « né en 2006 ou après », pas « moins de 20 ans » : l'âge
  /// change en cours de saison, l'année de naissance non.
  final int? bornFrom;
  final int? bornUntil;

  final bool openToOpportunitiesOnly;

  bool get isEmpty =>
      positions.isEmpty &&
      nationality == null &&
      bornFrom == null &&
      bornUntil == null &&
      !openToOpportunitiesOnly;

  /// Vrai quand la requête demande à la fois des postes et une nationalité.
  ///
  /// Firestore n'accepte **qu'un seul champ tableau** par index composite, donc
  /// les deux ne peuvent pas être filtrés côté serveur dans la même requête.
  /// Le repository filtre alors les postes côté serveur — c'est le critère le
  /// plus sélectif — et la nationalité sur le résultat.
  bool get needsClientSideNationalityFilter =>
      positions.isNotEmpty && nationality != null;
}

/// La recherche de talents, côté serveur.
///
/// Remplace l'hydratation de trois cents joueurs sur le téléphone suivie d'un
/// filtre en mémoire (`HomeFeedRepository.fetchSearchablePlayers`). Cette
/// approche marchait à onze joueurs et devenait absurde à deux mille : trois
/// cents lectures Firestore à chaque ouverture de la recherche, pour ignorer
/// les mille sept cents autres.
///
/// Toutes les requêtes commencent par `isSearchable`, posé par le serveur
/// (`functions/src/user_search_fields.ts`). Un compte désactivé, privé ou
/// incomplet n'est donc jamais parcouru — la sélection ne se fait pas après
/// coup, elle est dans l'index.
class TalentSearchRepository {
  const TalentSearchRepository({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// Le plafond d'une page.
  ///
  /// Un recruteur ne lit pas cent fiches ; il affine. Une page courte tient la
  /// facture de lecture et pousse à préciser la demande, ce qui est aussi le
  /// service qu'on lui rend.
  static const int pageSize = 30;

  Query<Map<String, dynamic>> buildQuery(TalentSearchQuery search) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .where('isSearchable', isEqualTo: true);

    if (search.positions.isNotEmpty) {
      query = query.where(
        'positionCodes',
        // `arrayContainsAny` plafonne a dix valeurs -- la raison pour laquelle
        // le vocabulaire s'arrete a dix postes.
        arrayContainsAny: search.positions
            .take(FootballPosition.maxPerQuery)
            .map((position) => position.code)
            .toList(),
      );
    } else if (search.nationality != null) {
      // Un seul champ tableau par index : la nationalite ne passe cote serveur
      // que si aucun poste n'est demande.
      query = query.where('nationalities', arrayContains: search.nationality);
    }

    if (search.openToOpportunitiesOnly) {
      query = query.where('openToOpportunities', isEqualTo: true);
    }

    if (search.bornFrom != null) {
      query = query.where(
        'birthYear',
        isGreaterThanOrEqualTo: search.bornFrom,
      );
    }
    if (search.bornUntil != null) {
      query = query.where('birthYear', isLessThanOrEqualTo: search.bornUntil);
    }

    return query.limit(pageSize);
  }

  /// Les joueurs correspondant à [search].
  ///
  /// Ne lève pas sur une absence d'index : Firestore répond alors
  /// `failed-precondition`, et le laisser remonter afficherait un écran vide
  /// indistinguable d'une recherche sans résultat. L'appelant reçoit l'erreur
  /// telle quelle et doit la dire.
  Future<List<AppUser>> search(TalentSearchQuery query) async {
    final snapshot = await buildQuery(query).get();

    final results = snapshot.docs
        .map((doc) {
          final data = doc.data();
          return AppUser.fromMap(<String, dynamic>{
            ...data,
            'uid': data['uid'] ?? doc.id,
          });
        })
        .where((user) => user.uid.trim().isNotEmpty)
        .toList();

    if (!query.needsClientSideNationalityFilter) {
      return results;
    }

    // Le second critere tableau, applique sur une page deja bornee : trente
    // documents au maximum, pas la collection.
    return results
        .where((user) => user.football.nationalities.contains(query.nationality))
        .toList();
  }
}
