# Socle de recherche de talents — spécification

Date : 31 août 2026. Statut : **spécification, aucun code écrit.**

Ce document décrit le travail à faire *après* la mise en production de
`1.0.7+29`. Rien ici ne doit être implémenté avant que l'AAB soit construit et
que la liste d'appareil de `docs/play-store-submission-1.0.7+29.md` soit
cochée sur un vrai téléphone. La raison est dans la section « Ordre » à la fin.

## Le problème, mesuré

Un recruteur de club européen ne cherche pas « une vidéo ». Il cherche *un
gaucher, milieu axial, né entre 2006 et 2008, ivoirien, libre*. Aujourd'hui
l'application ne peut répondre à aucun de ces quatre critères. Ce n'est pas un
manque d'écrans, c'est un manque de données interrogeables.

Constaté sur `adfoot-production` le 31 août 2026 (17 comptes, 11 joueurs) :

| Donnée | Comptes joueurs qui la portent |
| --- | --- |
| `profileVerified` | 0 / 11 |
| `country` | 0 / 11 |
| `birthDate` | 0 / 11 |
| `playerProfile` (quelconque) | 2 / 11 |
| Postes réellement saisis | `["Défense"]`, `["Attaquant"]` — texte libre |

Et côté requêtes :

- **Aucun index sur `users`** n'existe pour une recherche. Le seul déclaré est
  `emailVerified + dateInscription`, qui sert au nettoyage des comptes non
  vérifiés (`firestore.indexes.json`).
- La recherche actuelle hydrate jusqu'à **300 joueurs** sur le téléphone et
  filtre en mémoire (`home_screen.dart:527`, `HomeFeedRepository.fetchSearchablePlayers`).
  Correct à 11 joueurs. Intenable à 2 000 : 300 lectures Firestore à chaque
  ouverture de la recherche, et un filtre qui ignore les 1 700 autres.
- Les postes sont du **CSV libre** (`player_advanced_form.dart:236`,
  `_csvToList`). `video_search_matcher.dart` compense avec une table de
  synonymes à quatre familles, en français uniquement. On ne filtre pas du
  texte libre.

## Ce qui bloque techniquement, et qu'il faut connaître avant de coder

Trois contraintes réelles du dépôt, vérifiées, qui déterminent la forme de la
solution.

### 1. `canUpdateOwnProfile()` est une liste blanche stricte

`firestore.rules:227` utilise `changesOnly([...])`. **Tout nouveau champ écrit
par le client est refusé tant qu'il n'est pas dans cette liste.** Ce n'est pas
un détail d'implémentation : c'est la première chose à faire, et l'oublier
produit un `permission-denied` à l'enregistrement du profil.

### 2. `birthDate` n'est pas sur le document public

Il vit dans `users/{uid}/private/contact` et n'est chargé que pour le
titulaire (`includePrivateFields: uid == currentAuthUid`,
`profile_controller.dart:259`). Un visiteur — donc un recruteur — ne le reçoit
jamais.

C'est pour cette raison que `hasScoutReadyProfile` **n'exige pas l'âge**
aujourd'hui. L'avoir exigé, brièvement, rendait le verdict dépendant du
lecteur : le joueur voyait « Élite » sur son propre profil pendant qu'un
recruteur voyait « partiel » sur le même dossier. Un garde-fou
(`scout_ready_profile_guardrails_test.dart`, « the verdict is the same whoever
is looking ») empêche ce retour en arrière.

La sortie est un **`birthYear` public et dérivé** : l'année seule suffit à
filtrer une tranche d'âge, et n'expose pas une date de naissance complète. La
date exacte reste privée.

### 3. Un index doit exister *avant* le build qui s'en sert

C'est documenté dans `video_repository.dart` et c'est la raison d'être de
`scripts/check-backend-parity.ps1` : une requête sans index répond
`FAILED_PRECONDITION`, le repository l'attrape comme n'importe quel échec, et
l'écran a simplement l'air vide. Personne ne signale « il manque un index ».

## Le vocabulaire des postes

Liste fermée, stockée en **code**, affichée en libellé localisé. Le code est
ce qu'on indexe et compare ; le libellé est ce qu'on montre.

| Code | Libellé FR | Libellé EN |
| --- | --- | --- |
| `GK` | Gardien | Goalkeeper |
| `CB` | Défenseur central | Centre-back |
| `LB` | Latéral gauche | Left-back |
| `RB` | Latéral droit | Right-back |
| `DM` | Milieu défensif | Defensive midfielder |
| `CM` | Milieu central | Central midfielder |
| `AM` | Milieu offensif | Attacking midfielder |
| `LW` | Ailier gauche | Left winger |
| `RW` | Ailier droit | Right winger |
| `ST` | Attaquant | Striker |

Dix codes, alignés sur le vocabulaire que lisent les recruteurs. Un joueur en
choisit un à trois, dans l'ordre de préférence.

**Pourquoi des codes et pas les libellés :** un club néerlandais et un club
français doivent trouver le même joueur. Un libellé indexé enferme la base
dans une langue, et le jour où l'on ajoute l'anglais il faut réécrire toutes
les fiches.

### Migration des deux valeurs existantes

| Valeur actuelle | Compte | Code proposé | Confiance |
| --- | --- | --- | --- |
| `"Défense"` | 1 | `CB` | Faible — « Défense » ne dit pas axial ou latéral |
| `"Attaquant"` | 1 | `ST` | Moyenne — peut être un ailier |

Deux fiches, donc : **ne pas migrer automatiquement.** Demander aux deux
joueurs, ou laisser l'administration trancher depuis le portail. Un remappage
automatique inscrirait une donnée fausse dans la base qu'on prétend qualifiée,
et personne ne saurait ensuite qu'elle a été devinée.

## Tous les points de contact du poste, vérifiés

Balayage des deux dépôts le 31 août 2026. C'est la liste à modifier, et rien
d'autre ne touche au poste.

**Côté offre — le joueur :**

| Fichier | Ligne | Rôle |
| --- | --- | --- |
| `lib/screens/edit_profil_screen.dart` | 82, 380 | `position` en texte libre, **profil de base**, singulier |
| `lib/widgets/advanced/player_advanced_form.dart` | 58, 97 | `playerProfile.positions` en CSV libre, **et** réécrit `position` = `positions.first` |
| `lib/screens/profile_screen.dart` | 1105 | affiche `user.position` |
| `lib/screens/profile_screen.dart` | 1203 | affiche `playerProfile.positions` |
| `lib/utils/video_search_matcher.dart` | 161 | cherche dans `user.position` |
| `lib/models/user.dart` | 711 | `missingScoutRequirements` lit `positions` |

**Côté demande — le club :**

| Fichier | Ligne | Rôle |
| --- | --- | --- |
| `lib/models/offre.dart` | 19, 202 | `posteRecherche`, lu depuis `posteRecherche`\|`poste`\|`position` |
| `lib/screens/offres_form.dart` | 193 | champ libre « Poste recherché » |

**Dépôt admin :**

| Fichier | Ligne | Rôle |
| --- | --- | --- |
| `lib/dashboard/user_management_widget.dart` | 1570 | l'admin écrit `patch['position']` |
| `lib/models/user.dart` | 229, 524 | parse les deux, **et possède sa propre copie** du test `hasPosition` |

**Garde-fous qui casseront** (ils assertent sur des chaînes du source, donc à
mettre à jour dans le même commit, délibérément) :
`profile_advanced_cta_guardrails_test.dart:56,57,85` et
`video_search_matcher_test.dart:18,59`.

## Deux problèmes que ce balayage révèle

### A. Le joueur a deux champs de poste indépendants, qui peuvent se contredire

`position` (profil de base) et `playerProfile.positions` (profil avancé) sont
saisis dans deux écrans différents. Le formulaire avancé réécrit `position`
avec `positions.first`, mais l'écran de base peut le réécrire ensuite avec
n'importe quoi. Le même joueur peut donc porter `position: "Gardien"` et
`positions: ["Attaquant"]`, et deux écrans afficheront deux postes différents
pour lui.

Aucun compte n'est dans cet état aujourd'hui — un seul des deux champs est
rempli sur les deux fiches existantes — mais c'est une incohérence en attente,
et la codification est l'occasion de la supprimer : **un seul champ fait
autorité**, `positionCodes`, et `position` devient un libellé dérivé pour
l'affichage.

### B. La demande est en texte libre elle aussi

C'est le point qui change la conclusion. `Offre.posteRecherche` est un champ
libre, saisi dans `offres_form.dart:193`. **Codifier le poste du joueur seul ne
permet aucun rapprochement** : un club qui publie « cherche défenseur central
U19 » ne tombera jamais sur les joueurs marqués `CB`, parce que les deux côtés
ne parlent pas la même langue.

Les deux doivent être codifiés **dans la même livraison**, avec le même
vocabulaire. Sinon on aura payé le coût de la migration sans obtenir le
bénéfice — un club qui passe par nous et ne trouve personne.

L'offre reçoit donc `positionCodes` (array) au lieu d'un code unique : un club
cherche souvent « CB ou LB ».

## Les champs professionnels à ajouter

Au-delà du poste, ce qui décide réellement de la capacité d'un club européen à
agir. Vérifié : **aucun de ces champs n'existe aujourd'hui** dans
`lib/models/user.dart`.

| Champ | Type | Pourquoi il décide |
| --- | --- | --- |
| `nationalities` | `array<string>` ISO | **Le plus important après le poste.** Un joueur ivoirien avec un passeport français ne pose aucun problème de permis de travail ; le même sans passeport UE en pose un décisif. `country` est une localisation, pas une nationalité — les confondre est une erreur coûteuse |
| `contractStatus` | `free` \| `under_contract` \| `on_loan` \| `amateur` | Un joueur libre et un joueur sous contrat jusqu'en 2028 ne sont pas la même offre |
| `contractEndDate` | date (mois/année) | Un contrat qui expire dans six mois change tout le calendrier du recruteur |
| `currentClubLevel` | `pro` \| `semi_pro` \| `academy` \| `amateur` | Situe la performance : 12 buts en D3 ivoirienne et en académie U17 ne se lisent pas pareil |
| `heightCm`, `weightKg`, `strongFoot` | existants | À remonter en champs plats et à contraindre (`left`/`right`/`both`) |
| `birthYear` | `int` dérivé | Voir la contrainte 2 plus haut |

`contractStatus` et `nationalities` sont les deux à faire en priorité : ce sont
les seuls qui peuvent transformer un « intéressant » en « injoignable ».

## Le motif d'intégration : additif, jamais destructif

Trois phases. Aucune ne supprime un champ que la précédente lisait.

**Phase 1 — le socle serveur, sans nouveau build.** Liste blanche des règles,
trigger `onDocumentWritten('users/{uid}')`, index déclarés et déployés. Le
trigger dérive `positionCodes` de l'existant *quand il est certain*, et laisse
vide sinon. Aucun client ne change, aucun écran ne bouge, rien ne casse : les
nouveaux champs sont simplement ignorés par l'application installée.

**Phase 2 — le client écrit les deux.** Le formulaire devient un choix multiple
parmi les dix codes, pré-rempli par le mappage de l'existant. Il écrit
`positionCodes` **et** continue d'écrire `playerProfile.positions` en libellés,
pour qu'un client de la version précédente affiche toujours quelque chose.
Idem côté offre. Tout lecteur doit accepter un document qui ne porte que
l'ancien champ.

**Phase 3 — on bascule, puis on nettoie.** Quand tous les profils actifs
portent des codes, la recherche passe sur `positionCodes` et l'écriture du
champ libre s'arrête. La suppression du champ vient une version plus tard,
jamais dans la même.

Ce qui rend ce motif sûr tient en trois règles : **écrire en plus, jamais à la
place** ; **lire avec tolérance** ; **déployer règles et index avant le client
qui s'en sert**.

Ils **doublent** ce qui vit déjà dans `playerProfile`, volontairement :
Firestore n'indexe pas efficacement un champ imbriqué dans une map pour ce
type de requête, et le coût d'une poignée de champs dupliqués est très
inférieur à celui d'une recherche impossible.

| Champ | Type | Source | Exemple |
| --- | --- | --- | --- |
| `positionCodes` | `array<string>` | `playerProfile.positions` normalisées | `["CM","AM"]` |
| `birthYear` | `int` | dérivé de `birthDate` privé | `2007` |
| `countryCode` | `string` (ISO 3166-1 alpha-2) | dérivé de `country` | `"CI"` |
| `strongFoot` | `string` (`left`/`right`/`both`) | `playerProfile.physical.strongFoot` | `"left"` |
| `openToOpportunities` | `bool` | existe déjà | `true` |
| `isSearchable` | `bool` | calculé : joueur, actif, profil public, `hasScoutReadyProfile` | `true` |

`isSearchable` est le point 5 de l'analyse initiale — « ne montrer que les
fiches exploitables ». Le calculer et l'écrire **sans encore filtrer dessus**
permet de mesurer combien de joueurs il ferait apparaître avant de décider de
s'en servir. À la date de ce document, la réponse serait **0 sur 11** : filtrer
dessus tout de suite viderait l'application.

### Où l'écrire

Deux options, et la seconde est la bonne.

1. **Côté client**, dans `buildPatch()` de `player_advanced_form.dart`. Simple,
   mais chaque champ doit entrer dans la liste blanche des règles, et un client
   ancien continuerait d'écrire `playerProfile` sans les champs plats — la base
   se désynchroniserait silencieusement.
2. **Côté serveur**, dans un trigger `onDocumentWritten('users/{uid}')` qui
   dérive les champs plats de `playerProfile`, de `country` et du document
   privé. Aucune entrée dans la liste blanche (le SDK Admin l'ignore), aucune
   dépendance à la version du client, et la reprise de l'existant est un simple
   re-write de chaque document.

**Retenir l'option 2.** C'est aussi la seule qui peut lire `birthDate` dans le
document privé pour en dériver `birthYear` sans jamais exposer la date.

## Les index à déclarer

Dans `firestore.indexes.json`, puis déployés **avant** le build qui les
utilise :

```
users : isSearchable ASC, positionCodes ARRAY, birthYear ASC
users : isSearchable ASC, countryCode ASC, birthYear ASC
users : isSearchable ASC, positionCodes ARRAY, countryCode ASC
users : isSearchable ASC, openToOpportunities ASC, birthYear ASC
```

Quatre index couvrent les combinaisons qu'un recruteur demande réellement.
Ils sont sans effet tant qu'aucun document ne porte les champs : les déployer
tôt ne coûte rien et supprime le risque d'ordonnancement.

`npm run backend:parity:check:production` doit être vert après le déploiement
et **avant** le build.

## La requête qui remplace le filtre client

`HomeFeedRepository.fetchSearchablePlayers(limit: 300)` disparaît au profit
d'une requête serveur paginée, filtrée sur `isSearchable`, `positionCodes`
(`array-contains-any`, 10 valeurs maximum — d'où dix codes et pas trente),
`birthYear` (plage) et `countryCode`.

Conserver `video_search_matcher.dart` pour la recherche en texte libre : les
deux coexistent, l'un pour « je cherche un nom », l'autre pour « je cherche un
profil ».

## Ce qui reste hors de cette spec

Les points 6, 7 et 8 de l'analyse du 31 août, délibérément non spécifiés ici
parce qu'ils dépendent tous de ce socle :

- **Métadonnées football sur la vidéo** (type, date, niveau d'adversaire,
  poste occupé). `Video` n'en a aucune aujourd'hui.
- **Shortlist recruteur.** Rien ne permet à un recruteur de mettre un joueur de
  côté. Nouvelle collection, nouvelles règles.
- **Fil ordonné par pertinence.** Le fil est purement chronologique
  (`approvedAt DESC`).

## Ordre, et pourquoi il n'est pas négociable

1. Construire l'AAB `1.0.7+29`, le téléverser en test interne.
2. Cocher les onze cases de la liste d'appareil, sur un vrai téléphone, depuis
   le build installé par Play.
3. Promouvoir en production.
4. **Ensuite seulement**, branche `talent-search` : règles, trigger, index,
   puis client.

Les points 1 à 3 d'abord parce que ce socle touche exactement les surfaces qui
n'ont jamais tourné sur un appareil — le formulaire de profil, la recherche, le
chemin de sauvegarde. Les modifier avant le test terrain ne rend pas le test
plus long : il le rend **ininterprétable**. Le jour où quelque chose casse sur
le téléphone, plus personne ne saura si c'est la nouveauté ou le pipeline
existant.

Et une contrainte matérielle : une fois l'AAB de `29` construit, tout commit
supplémentaire impose `versionCode 30` et un nouveau build — plus d'une heure
à chaque fois.
