# Audit de la lecture vidéo, 17 octobre 2026

Point de départ : « quand on quitte l'accueil en cours de lecture puis qu'on
revient, on a l'impression que la vidéo se charge de nouveau ».

L'impression est exacte, et ce n'est pas seulement le réseau. Trois causes
distinctes s'additionnent, toutes vérifiées dans le code et deux d'entre elles
chiffrées sur la production.

## Ce qui a été mesuré, pas supposé

Relevé sur `client_logs` de `adfoot-production`, du 1er au 17 octobre, 105
sessions de lecture, via `scripts/check-feed-playback-metrics.js`.

| Indicateur | Valeur |
| --- | --- |
| Sessions ayant rendu une première image | **78 %** |
| Temps jusqu'à la première image, moyenne | 1 399 ms |
| Taux de complétion | 18 % |
| Rebuffering moyen par session | 0,39 |

Par palier réseau :

| Palier | n | 1re image | Temps 1re image | Rebuffer |
| --- | --- | --- | --- | --- |
| high | 32 | 81 % | **516 ms** | 0,34 |
| medium | 29 | 66 % | 1 282 ms | 0,31 |
| low | 44 | 84 % | **2 080 ms** | 0,43 |

Par hauteur de source, et c'est la ventilation la plus parlante :

| Hauteur | n | 1re image | Temps 1re image | Complétion |
| --- | --- | --- | --- | --- |
| 480p | 15 | 93 % | 3 055 ms | 60 % |
| 576p | 13 | 85 % | 1 447 ms | 0 % |
| 720p | 70 | 79 % | 961 ms | 13 % |
| **1080p** | 7 | **29 %** | 1 607 ms | 14 % |

Par contexte d'entrée : `home` porte 103 des 105 sessions, à 78 % de première
image. Les 2 sessions de `profile` sont à **100 % et 112 ms**, parce que leur
fichier était déjà sur disque. C'est la référence de ce que vaut un cache
chaud : un ordre de grandeur.

## Cause 1 : quitter l'accueil détruit tous les lecteurs, y compris celui à l'écran

`MainScreen` échange le corps de ses onglets au lieu de les garder dans un
`IndexedStack`. Quitter Accueil détruit donc `HomeScreen`, puis
`VideoFeedPager.dispose()`, qui appelle `VideoFocusOrchestrator.onDispose()` :

```dart
Future<void> onDispose() async {
  await videoManager.pauseAll(contextKey);
  await videoManager.disposeAllForContext(contextKey);   // tout, sans exception
}
```

C'est un choix assumé et documenté : rendre les instances `MediaCodec`, dont
l'épuisement a provoqué deux incidents de production en août 2026.

Mais le code contient déjà le traitement plus fin, et l'applique ailleurs.
Quand l'application passe en arrière-plan, `_releaseNeighboursForBackground()`
fait exactement ce qu'il faudrait ici :

> « The visible video is deliberately kept: resuming has to be instant, and it
> is the one player whose bytes are not wasted. »

Deux situations identiques du point de vue de l'utilisateur, deux traitements
opposés. Le passage en arrière-plan garde le lecteur visible ; le changement
d'onglet le jette.

Et le filet existe déjà pour le risque que cela ferait courir.
`_enforceGlobalLimit` plafonne à 4 lecteurs pour toute l'application et libère
en premier « a context nobody is looking at ». Garder un seul lecteur
d'Accueil pendant une visite au profil est précisément le cas que ce
limiteur a été écrit pour absorber.

## Cause 2 : la vidéo regardée n'est jamais écrite sur le disque

Le chemin d'initialisation, dans `VideoManager.loadVideo()` :

1. fichier présent dans le cache disque, on le joue, c'est local et immédiat ;
2. absent et lecture active, on **diffuse en flux avec `skipCache: true`**,
   donc **rien n'est écrit** ;
3. absent et préchargement lointain, on télécharge le fichier entier.

Le `skipCache: true` est justifié : sans lui, `cached_video_player_plus`
lançait un second transfert des mêmes octets et la lecture perdait la course.
`_shouldWarmCacheAfterStreamInit` retourne d'ailleurs toujours `false`, avec
la même raison.

La conséquence n'a pas été tirée. Le seul endroit qui remplit le cache est
`warmVideoFile`, appelé uniquement par le planificateur de préchargement, qui
**exclut explicitement la vidéo active** :

```dart
if (candidateUrl.isEmpty || candidateUrl == active) continue;
```

Donc la vidéo que l'utilisateur regarde n'atteint le disque que s'il **fait
défiler au-delà**, moment où elle devient la voisine d'une autre. Celui qui
ouvre l'accueil, regarde la première vidéo, va au profil et revient n'a jamais
fait défiler : le fichier n'existe nulle part, et le retour **retélécharge
réellement**, depuis le début.

Le cache a pourtant 600 Mo de budget et 15 jours de rétention. Il n'est pas
plein, il est mal rempli.

Il existe déjà un moment nommé où un téléchargement de fond redevient sûr :
`markActivePlaybackStable`, soit trois tics de 700 ms sans à-coup. Le code y
libère les préchargements de fichiers des voisins. Il pourrait y ajouter le
fichier actif, sans toucher à la phase fragile du démarrage.

## Cause 3 : la position de lecture n'est jamais restaurée

Recherche de `seekTo` dans tout `lib/` : quatre occurrences, toutes dans
`tiktok_video_player.dart`, toutes déclenchées par l'utilisateur, barre de
progression et double tap.

**Aucune restauration de position n'existe.** Quelle que soit la cause 1 ou 2,
revenir sur l'accueil fait repartir la vidéo à 0:00. Même avec un fichier sur
disque et un lecteur instantané, l'utilisateur verrait la vidéo recommencer,
ce qui se lit exactement comme un rechargement.

C'est la cause la moins coûteuse à corriger et celle qui pèse le plus sur la
perception.

## Hors sujet initial, mais plus grave : le 1080p ne démarre pas

**71 % des sessions en 1080p ne rendent jamais de première image.** Sur 7
sessions seulement, donc à confirmer, mais la direction est nette et cohérente
avec l'incident déjà documenté dans le code (« heaviest ready video is 71 MB
at 10.6 Mb/s »).

La sélection adaptative n'est pas en cause par absence : vérifié sur
`config/streaming` en production, `adaptiveEnabled: true`, `rolloutPercent:
100`. Et la seule vidéo prête du catalogue porte bien deux rendus, 1080p et
480p.

La règle est la suivante : au-dessus de 6 Mb/s mesurés, le palier est `high` et
le 1080p est servi tel quel ; en dessous, la hauteur est plafonnée à 540 ou
360 et le 480p est choisi. Le défaut probable est donc que 6 Mb/s mesurés une
fois ne garantissent pas de pouvoir soutenir un 1080p non contraint en débit
pendant toute la lecture.

À traiter séparément : cela touche tous les lecteurs, pas seulement le retour
sur l'accueil.

## Ce qu'il faut faire, par rapport valeur sur risque

| # | Correctif | Effet | Risque | État |
| --- | --- | --- | --- | --- |
| A | Restaurer la position de lecture au retour | supprime le « ça recommence » | faible | **fait** |
| B | Garder le lecteur visible en quittant l'onglet, comme à la mise en arrière-plan | retour instantané | moyen, amorti par `_enforceGlobalLimit` | à décider |
| C | Écrire le fichier actif sur disque à `markActivePlaybackStable` | supprime le retéléchargement | moyen, octets dupliqués | à décider |
| D | Enquêter sur l'échec du 1080p | 71 % de non-démarrage | à mesurer d'abord | à décider |

A et B se complètent : B rend le retour instantané quand le lecteur a survécu,
A couvre le cas où le limiteur global l'a repris. C travaille pour les deux en
garantissant que le pire cas reste une ouverture de fichier local.

## Comment reproduire les mesures

```powershell
node .\scripts\check-feed-playback-metrics.js --project-id adfoot-production `
  --credentials .credentials\adfoot-production-ops.json --since 2026-10-01T00:00:00Z

node .\scripts\set-streaming-config.js --project-id adfoot-production `
  --credentials .credentials\adfoot-production-ops.json --show

node .\scripts\list-ready-playback-contracts.js --project-id adfoot-production `
  --credentials .credentials\adfoot-production-ops.json --limit 40 --scan 300
```

Les trois sont en lecture seule. `set-streaming-config.js --show` n'écrit rien.

## Correctif A, livré le 17 octobre

`lib/videos/domain/resume_position_store.dart`, dixième collaborateur de
`VideoManager`. Le lecteur enregistre sa position à chaque tic, dans le même
passage qui alimente déjà les métriques de lecture, parce que c'est le seul
endroit qui voit la position tant que le contrôleur est vivant. À la
reconstruction, `_restoreResumePositionIfNeeded` ramène le lecteur au bon
endroit avant de lancer la lecture.

Trois règles décident qu'une position mérite d'être rendue : au moins trois
secondes, pas dans les cinq dernières secondes du clip, et le contrôleur doit
être au début. Cette dernière protège le cas où reprendre serait pire que ne
rien faire : une vidéo promue depuis un préchargement, ou mise en pause à la
main par l'utilisateur, est déjà quelque part volontairement.

La mémoire survit à `disposeAllForContext`, et c'est délibéré : cet appel
**est** le moment qu'elle compense. Elle est bornée à 64 entrées à la place,
la moins récemment touchée partant en premier.

Le garde-fou `video_architecture_test.dart` a refusé la première version, qui
mettait la table et ses seuils dans `VideoManager`. C'est exactement ce qui
était arrivé à la porte de lecture avant elle. La logique est donc partie dans
son propre fichier et le manager ne garde que quatre méthodes de passe-plat.

Ce que A ne corrige pas, et qui reste entier : le retéléchargement de la
cause 2, et le redémarrage à froid de la cause 1. Reprendre au bon endroit
rend l'attente honnête, elle ne la supprime pas.
