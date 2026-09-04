# Reprise — stabilisation avant production, 3 septembre 2026

Ce document existe pour qu'une nouvelle session reprenne le travail sans le
redécouvrir. Il dit où en est la branche, ce qui a été **vérifié** plutôt que
supposé, et ce qui reste — dont rien n'est du code.

Plan de référence (numérotation 0, 1..7 et 3 bis utilisée partout ici) :
<https://claude.ai/code/artifact/a36053c5-c8de-4876-beac-d50463834e39>

## État

Branche `observabilite-echecs-subis`, **11 commits d'avance sur `master`**,
jamais fusionnée, jamais poussée. Arbre propre à `72f1b03`.

- `flutter test` : **878 verts**
- `flutter analyze` : propre
- Parité backend : **verte** au 2026-09-03 20:06 — deux jeux de règles
  identiques au dépôt, **20/20** index déployés et `READY`, TTL actifs

`pubspec.yaml` est déjà à **`1.0.7+33`**. Le `32` est construit
(`artifacts/android/adfoot-production-20260902T134118Z.aab`, 2 septembre 13:41),
installé depuis Internal testing, et son versionCode est donc consommé — mais il
**précède les six commits ci-dessous** et n'en contient aucun.

Le prochain build est donc `33`, et il doit être vérifié contre le bundle, pas
contre la source : `scripts/check-aab-contents.ps1` tourne automatiquement à la
fin de `build-android-release.ps1`. C'est le garde-fou né du `31`, qui avait
embarqué le snapshot Dart du `30` octet pour octet pendant que toutes les portes
de qualité, qui lisent la source, restaient vertes.

## Les six commits de cette session

| Commit | Ce qu'il règle |
|---|---|
| `b5d435b` | 7 contrôleurs (40 chemins) : `AppLogger.debug` → `warning` |
| `f54b677` | tiret bas d'une fonction locale (analyse) |
| `3b6aa70` | `scripts/report-account-deletion-impact.mjs`, corrigé sur le vrai portillon |
| `b96810d` | 3 services muets : init du lecteur vidéo, parse d'événement, jeton FCM |
| `e73c6b9` | la fiche d'événement montre enfin l'affiche et les vues |
| `72f1b03` | filtre par poste côté serveur, avec son index |

Les messages de commit portent le raisonnement complet ; ils sont la source la
plus fiable sur le « pourquoi ».

## Ce qui reste — et pourquoi je ne peux pas le faire

### 1. L'unique offre en production (ligne 3 bis) — RÉGLÉ le 4 septembre

Le script tourne bien depuis l'assistant, contrairement à ce qui était écrit
ici. Mais il n'avait plus rien à faire : la marche à blanc du 4 septembre
répond `ignore — porte deja le vocabulaire code`, et `--apply` écrit `Rien a
ecrire`.

`report-career-content.mjs` confirme la reprise : `positionCodes` vaut `LB`,
`ageCategories` est renseigné, les anciens champs sont toujours là. La seule
case vide est `clubLevel`, et c'est correct — le `niveau` libre disait `U19`,
qui est une catégorie d'âge et ne correspond à aucun niveau de club. Il n'y a
rien à deviner de plus.

La reprise vient très probablement du portail admin : `2251b74` y a fait de
`offre.dart` un miroir exact du fichier mobile, `toMap` y écrit donc les
champs codés, et il suffit d'avoir ré-enregistré l'offre depuis la console
pour qu'elle reparte codée. Conséquence utile : **les deux côtés écrivent
maintenant le vocabulaire codé**, donc le problème ne se reproduira pas sur
les offres à venir.

### 2. Du contenu réel

Production tient **une offre et un événement** — inchangé au 4 septembre. Le
filtre par poste est déployé et indexé, mais il n'a rien à trier. Avant toute
proposition qui dépend du volume, rejouer la mesure :

```
node scripts/report-career-content.mjs
```

**Tranché le 4 septembre : le poste est obligatoire à la publication.** Le fil
interroge `positionCodes arrayContainsAny`, donc une offre publiée sans poste
n'était pas « moins visible » mais introuvable dans toute recherche par poste,
sans que son auteur puisse le constater. Le contrôle passe par un `FormField`
et non par un test dans `_submitForm` : le poste est validé par le même
`validate()` que le titre, et l'erreur se pose sous les puces au lieu du
message général qui ne dit pas où regarder.

Le portail admin ne fait que **lire** `offres` — `snapshots()` et une `Query`,
aucune écriture. Le mobile est donc la seule porte, et l'exigence vaut
partout ; il n'y a pas de parité à rattraper côté admin.

Un effet de bord assumé : une offre ancienne dépourvue de poste ne peut plus
être ré-enregistrée sans qu'on lui en coche un. Aucune n'est dans ce cas en
production — l'unique offre porte `LB`.

### 3. La vérification sur appareil

Le chemin **téléversement → URL → affichage** de l'affiche d'événement n'a
jamais tourné contre un vrai Storage : il n'est devenu possible qu'au
déploiement des règles, à 20:06.

Deux points à surveiller, parce qu'ils sont conçus pour être silencieux :

- **Éditer un événement ne doit pas effacer son affiche.** Défaut latent
  corrigé dans `61e2e54`, invisible tant qu'aucun événement n'en portait.
- **Un refus remonte désormais dans `client_logs`** en `warning`, avec sa pile,
  au lieu de disparaître.

Le 4 septembre, `44ed0eb` a corrigé **un second chemin** du même défaut, que
`61e2e54` avait laissé : le menu de statut de la liste reconstruit un `Event`
complet pour `updateEvent` et y codait `flyerUrl: null` en dur. Passer un
événement de « Ouvert » à « Fermé » supprimait son affiche. Le test épinglait
la ligne fautive, recopiée depuis le formulaire où elle est juste.

Donc, sur appareil, **changer le statut après avoir attaché une affiche** fait
partie du test, et pas seulement rouvrir le formulaire d'édition.

Deux comportements normaux à ne pas prendre pour des pannes :

- Le compteur de vues **n'augmente jamais pour l'organisateur** : la règle
  `canMutateEventViews` exige `organisateur.uid != request.auth.uid`. Il faut
  un second compte pour le voir bouger.
- Une vue est comptée **à l'apparition dans la liste**, pas à l'ouverture de la
  fiche — même sémantique que les offres, délibérément.

La liste complète des contrôles par build est dans
`docs/play-store-submission-1.0.7+32.md` (dossier courant, 2 septembre) et la
liste générique dans `docs/checklists/android-release-checklist.md`. Un nouveau
dossier sera dû pour le `33`.

## Deux contraintes de conception à ne pas rejouer

**Un seul champ tableau par index composite Firestore.** C'est pourquoi le fil
des offres filtre `positions` côté serveur et `ageCategories` / `clubLevel` sur
la page déjà chargée. `TalentSearchRepository` avait tranché le même problème
de la même façon, dans l'autre sens du rapprochement. Ce n'est pas un choix de
produit et ce n'est pas négociable sans changer d'index.

**`AppLogger.debug` ne quitte jamais l'appareil** : `_shouldSendToRemote`
renvoie `false` pour ce niveau sans condition. C'est toute la raison d'être de
la conversion en `warning`, échantillonné à 15 % en production.

Il reste **46** sites `debug`-dans-`catch` dans `lib/`, et c'est **délibéré** :
le cache vidéo retombe proprement sur le réseau, et les chemins de préchauffage
d'authentification sont des transitoires volontaires, déjà gardés par
`kDebugMode` et documentés comme tels. Les convertir ferait du bruit sur des
conditions que l'application absorbe par conception.

## Avant tout nouveau build

```
powershell -File scripts\check-backend-parity.ps1 -Environment production
```

Un déploiement de règles peut réussir **à moitié** : ça s'est produit deux fois
le 3 septembre, Firestore passant et Storage non, sans le moindre message.
`--only storage` et `--only firestore:indexes` sont des cibles séparées.
