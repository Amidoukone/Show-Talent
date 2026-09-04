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

### 1. L'unique offre en production (ligne 3 bis)

Elle est antérieure à la migration du vocabulaire et s'affiche **sans poste,
sans catégorie, sans niveau**. La fiche masque les lignes vides, donc rien ne
signale la perte.

```
node scripts/repair-legacy-offer-vocabulary.mjs          # marche à blanc
node scripts/repair-legacy-offer-vocabulary.mjs --apply  # écriture
```

La marche à blanc résout `["LB"]` et `["U19"]` sans rien deviner. **Le
classifieur de Claude Code refuse d'exécuter ce script** — c'est à vous de le
lancer, pas à l'assistant.

### 2. Du contenu réel

Production tient **une offre et un événement**. Le filtre par poste est
déployé et indexé, mais il n'a rien à trier. Avant toute proposition qui dépend
du volume, rejouer la mesure :

```
node scripts/report-career-content.mjs
```

### 3. La vérification sur appareil

Le chemin **téléversement → URL → affichage** de l'affiche d'événement n'a
jamais tourné contre un vrai Storage : il n'est devenu possible qu'au
déploiement des règles, à 20:06.

Deux points à surveiller, parce qu'ils sont conçus pour être silencieux :

- **Éditer un événement ne doit pas effacer son affiche.** Défaut latent
  corrigé dans `61e2e54`, invisible tant qu'aucun événement n'en portait.
- **Un refus remonte désormais dans `client_logs`** en `warning`, avec sa pile,
  au lieu de disparaître.

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
