# Transition sans rupture de `users` vers `public_profiles`

> **Lire d'abord « Mesure du 13 octobre 2026 », plus bas.** Les deux relevés
> d'état qui ouvrent ce document (28 septembre, 2 octobre) sont périmés : ils
> décrivent une production sous règles transitoires, alors que les règles
> **finales** y sont déployées depuis le 10 octobre. Agir sur eux conduirait à
> redéployer les règles transitoires et à réouvrir une exposition des profils
> plus large que prévu.

**État au 28 septembre 2026 :** les données de test ont été remises à zéro dans
staging et production ; les index sont `READY`, les deux Functions de
projection/backfill v3 sont déployées, et les projections v3 sont complètes
dans les deux projets. Les règles finales sont déployées sur staging seulement.
Les règles transitoires sont déployées en production après test sur émulateur ;
la validation sur les anciens et nouveaux builds, puis la bascule vers les
règles finales, restent à faire. Voir
`test-data-reset-and-migration-2026-09-28.md`.

**Contrôle distant du 2 octobre 2026 :** les règles Firestore de production
diffèrent toujours des règles finales `firestore.rules`; le `updateTime` remonté
par l'API Rules est le 28 septembre à 21:11 UTC. Les règles Storage correspondent
au dépôt, les 31 index déclarés sont `READY` et les deux TTL contrôlés sont
`ACTIVE`. Cette observation confirme l'état transitoire attendu à cette date,
mais ne mesure toujours pas les versions mobiles actives ni les parcours réels.

**Mesure du 13 octobre 2026 — cet état transitoire n'existe plus.** Les deux
paragraphes ci-dessus décrivent une production qui a changé le 10 octobre. Ne
pas s'en servir pour décider quoi déployer ; ils restent ici comme historique.

Relevé en lecture seule depuis ce checkout (`npm.cmd run
backend:parity:check:production`, qui compare aux règles **finales**) :

| Contrôle | Résultat |
| --- | --- |
| Firestore : règles déployées vs `firestore.rules` | **identiques** (SHA256 `da5f5bd9…6dd6`), `updateTime` 2026-10-10T17:39:34Z |
| Storage : règles déployées vs `storage.rules` | **identiques** (SHA256 `1a81175d…2be4`), `updateTime` 2026-10-05T10:00:18Z |
| Index déclarés / déployés | **44 / 44**, tous `READY`, aucun index en trop |
| TTL `client_logs.expireAt`, `video_action_logs.expireAt` | **ACTIVE** |

Autrement dit : **les règles finales sont en production depuis le 10 octobre**.
La phase 3 point 2 est faite. Ce qui n'était pas fait, et que personne n'avait
mesuré, c'est l'autre moitié de la fermeture — les flags héritée restent en
posture *phase 1* alors que les règles sont en *phase 3*. C'est cette asymétrie
qui est dangereuse, pas les règles.

Posture réelle des trois flags, relevée dans `functions/.env.production` : les
trois sont **absents du fichier**, donc chacun prend son défaut de code, et ces
défauts sont exactement la posture phase 1 attendue — aucune dérive :

| Flag | Défaut de code | Effet actuel |
| --- | --- | --- |
| `ENABLE_LEGACY_CV_URL_MIGRATION` | `!== "true"` → inactif | aucune conversion d'URL CV |
| `ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP` | `=== "true"` → inactif | les tableaux de suivi sont conservés |
| `MIRROR_LEGACY_FOLLOW_ARRAYS` | `!== "false"` → **actif** | les callables écrivent encore les tableaux |

Résidu réellement présent en production, mesuré par
`npm.cmd run legacy:residue:check:production`
(`scripts/check-legacy-profile-residue.mjs`, lecture seule) :

| Résidu | Compte | Conséquence |
| --- | --- | --- |
| `users.cvUrl` encore en `http…` (URL à jeton) | **0 sur 4 comptes** | `ENABLE_LEGACY_CV_URL_MIGRATION` n'a **rien** à convertir |
| `users.followersList` / `followingsList` présents | 4 comptes | 8 champs à supprimer |
| Arêtes de suivi dans ces tableaux | **0** | la suppression des tableaux est un no-op observable |
| Documents dans `following` / `followers` | **0** | personne ne suit personne en production |
| `users.fcmToken` hérité | **0** | `migrateLegacyFcmTokens` a terminé |
| `public_profiles_and_follows_v5` | `completed: true` | — |
| `conversation_sort_dates_v1` | `completed: true` | — |
| `public_profiles_follow_cleanup_v1` | **absent** | le nettoyage n'a jamais tourné |

Et la projection est complète : 4 comptes, 4 `public_profiles`, 0 manquant,
0 orphelin (`npm.cmd run` → `scripts/inventory-test-data.mjs`).

**Ce que la mesure change, décision par décision.**

*L'URL du CV n'est plus un sujet.* La crainte initiale — des URL de
téléchargement à jeton durable exposées sur des profils lisibles — ne porte sur
aucun document en production. Et elle ne peut plus réapparaître : les règles
finales déployées imposent le format `gs://` à toute écriture de `cvUrl`
(`ownerCvUrlChangeIsSafe`), et aucune Cloud Function n'écrit de valeur `http`
— les seules écritures restantes dans `functions/src/` sont des suppressions.
Activer le flag convertirait zéro document. Le laisser inactif est donc le bon
choix, et pour une raison mesurée, non par prudence : il n'y a rien à
convertir et aucun flux entrant. À reprendre seulement si
`legacy:residue:check:production` compte un jour autre chose que 0.

*Arrêter l'écriture des tableaux est sûr pour le build en cours.* Vérifié dans
ce checkout, et c'est le point qu'il fallait trancher avant tout : le client
actuel ne dépend **pas** du tableau stocké. `FollowController._bindFollowingStream`
s'abonne à `FollowRepository.watchFollowingIds`, qui lit la sous-collection
`users/{uid}/following` filtrée sur `active == true`, puis **écrase**
`user.followingsList` avec ce résultat. Le tableau Firestore ne sert que
d'amorce au chargement du document (`AppUser.fromMap`, qui retombe sur `[]`
quand le champ est absent) et de cache optimiste local. Les trois lectures de
`followingsList` dans l'interface — `profile_screen.dart`,
`video_action_rail.dart`, `smart_video_player.dart` — consomment cette valeur
hydratée, pas le champ brut.

Conséquence : `MIRROR_LEGACY_FOLLOW_ARRAYS=false` ne retire rien au build 48/49.
Le seul effet résiduel possible est un écart de quelques centaines de
millisecondes au démarrage à froid, entre le chargement du document et la
première émission du flux de relations, pendant lequel un bouton « Suivre »
pourrait s'afficher non-suivi. Cet écart existe déjà aujourd'hui pour tout
compte dont le tableau est en retard.

*Et la suppression des tableaux ne casse pas la suppression de compte.*
`cleanupFollowReferences` (`functions/src/admin_account_actions.ts`) parcourt
d'abord les arêtes de relations — c'est le chemin principal, qui supprime les
documents `following/{uid}` et décrémente les compteurs côté serveur — puis
traite les tableaux en second, sous le commentaire « Compatibility while the
one-time array migration is still running ». Retirer les tableaux retire un
filet de compatibilité, pas le mécanisme.

**Conclusion : la fermeture de la migration coûte un déploiement backend qui
supprime 8 champs vides.** C'est aussi peu cher que ce le sera jamais, et
l'argument de la fenêtre qui se referme portait moins loin qu'annoncé : le
risque n'était pas de casser d'anciens clients — les règles finales sont
déployées depuis le 10 octobre et ce basculement est derrière nous — mais de
laisser le mirroring hérité en place jusqu'à ce que de vrais suivis existent,
moment où ces tableaux cessent d'être vides et où leur suppression devient une
vraie migration de données.

### Procédure de fermeture, dans cet ordre

Rien ci-dessous n'est exécuté par ce document. L'ordre vient de `CLAUDE.md` :
le backend d'abord, et surtout **une release backend distincte** pour ce
changement, afin que la suppression de champs ne voyage pas avec un autre
correctif.

1. Relever l'état d'avant, pour pouvoir comparer :
   `npm.cmd run legacy:residue:check:production`.
2. Dans `functions/.env.production`, ajouter les deux lignes — et seulement
   celles-là :

   ```
   MIRROR_LEGACY_FOLLOW_ARRAYS=false
   ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP=true
   ```

   Ne pas ajouter `ENABLE_LEGACY_CV_URL_MIGRATION` : voir la mesure ci-dessus.

   **Appliqué le 13 octobre 2026**, avec le commentaire d'intention et la
   procédure de retour arrière, et vérifié par
   `npm.cmd run functions:env:check:production` qui résout bien les deux
   valeurs. Attention : `functions/.gitignore` ignore `.env.*`, donc cette
   édition **ne vit que sur le poste où elle a été faite**. Un déploiement
   lancé depuis une autre machine ou depuis un runner CI partirait sans les
   flags et ne fermerait rien — sans erreur visible. Déployer depuis ce poste,
   ou reporter les deux lignes là où le déploiement part.
3. `npm.cmd run functions:deploy:production`. À lancer depuis le shell de
   l'opérateur : le sandbox de l'assistant n'a pas de session Firebase CLI et
   échoue en 401 sur `firestore.googleapis.com`, message trompeur à l'appui.

   **Fait le 13 octobre 2026 vers 17:15 UTC** : 59 fonctions mises à jour,
   `backfillPublicProfiles` comprise, les deux flags visibles dans les valeurs
   effectives du log. À noter pour la prochaine fois : le CLI a affiché
   `Authentication Error ... run firebase login --reauth` avant de déployer
   quand même. Le message ne vient pas du script, qui n'appelle que
   `firebase.cmd deploy` ; il annonce une session à renouveler avant le
   déploiement suivant.
4. Attendre un passage de `backfillPublicProfiles`, qui est horaire. Avec le
   flag de nettoyage actif, la Function écrit son point de reprise dans
   `migration_state/public_profiles_follow_cleanup_v1` et non plus dans
   `…_v5` (`functions/src/cleanup.ts`) : la fermeture n'est finie que quand ce
   **nouveau** document porte `completed: true`.

   Le déploiement ne déclenche pas ce passage. Un relevé fait juste après
   montre donc encore les tableaux et l'absence du nouveau point de reprise :
   c'est attendu, et ne doit pas être lu comme un échec du flag. Pour ne pas
   attendre l'heure : console Google Cloud -> **Cloud Scheduler** -> projet
   `adfoot-production` -> job
   `firebase-schedule-backfillPublicProfiles-europe-west1` -> **Force run**.
   L'opération est idempotente — `refreshUserSearchFields` et
   `syncPublicProfile` sont rejoués par compte, et `migrateLegacyFollowEdges`
   ne trouve rien à migrer puisque les tableaux sont vides.
5. Confirmer par la mesure, pas par l'absence d'alerte :

   ```powershell
   npm.cmd run legacy:residue:gate:production
   ```

   La variante `gate` sort en code non nul tant qu'un résidu subsiste ; c'est
   la forme à utiliser après le déploiement.

   **Fait le 13 octobre 2026, après un *Force run* du job Cloud Scheduler.**
   Le gate sort en **code 0** :

   | Signal | Avant | Après |
   | --- | --- | --- |
   | Comptes portant les tableaux de suivi | 4 | **0** |
   | `public_profiles_follow_cleanup_v1` | absent | **`completed: true`** |
   | `blockers` | 1 | **aucun** |

   Et le contrôle strict repasse vert juste après
   (`npm.cmd run backend:parity:check:production`, code 0 : règles identiques,
   44/44 index `READY`, les deux TTL `ACTIVE`). **La migration `users` vers
   `public_profiles` est fermée.**

   Un piège d'interprétation rencontré au passage : ce même contrôle avait
   d'abord échoué sur `request to https://oauth2.googleapis.com/token failed`,
   une panne réseau pendant la récupération du jeton OAuth. Le script sort
   alors en code 1 avec le message « Deploy the backend before building », qui
   décrit une dérive alors qu'aucune comparaison n'a eu lieu. Relancer avant
   de conclure : un échec de parité nomme toujours le jeu de règles ou l'index
   en cause.
6. Vérifier sur appareil que suivre et ne plus suivre fonctionnent encore, et
   qu'une suppression de compte ne laisse pas de compteur de suiveurs décalé.
7. Retirer `firestore.transition.rules` des artefacts de release (phase 3
   point 3). **Ce n'est pas une suppression de fichier, et c'est la
   découverte du 13 octobre.** L'artefact est tenu en place par un garde-fou
   écrit exprès pour empêcher qu'on le retire par inadvertance. Quatre
   endroits, à traiter ensemble :

   | Endroit | Ce qu'il affirme aujourd'hui |
   | --- | --- |
   | `firestore.transition.rules` | le jeu de règles lui-même |
   | `test/rules/firestore-transition-rules.test.mjs` | une suite de tests entière qui le lit |
   | `test/backend_parity_gate_guardrails_test.dart` | que le script npm `…:transition` **doit** exister et que le gate **doit** citer le fichier |
   | `package.json` | `backend:parity:check:production:transition` |

   Supprimer le fichier seul casse deux suites de tests. Le garde-fou Dart
   demande en plus d'être réécrit pour affirmer l'inverse — que le mode
   transitoire a disparu — sinon il protège un artefact mort.

   Ce travail n'est **pas un préalable au lancement** : rien dans la chaîne de
   release ne dépend du fichier, et il n'est jamais déployé. Le seul risque
   réel est qu'un opérateur lance `backend:parity:check:production:transition`,
   le voie réussir, et en conclue à tort que la production est encore en état
   transitoire. D'ici là, c'est le contrôle strict
   `backend:parity:check:production` qui fait foi. À planifier après les
   soumissions, en une modification cohérente des quatre endroits.

### Le piège des fichiers d'environnement, trouvé après coup

Avoir édité `functions/.env.production` seul ne suffisait pas, et l'oubli était
silencieux. `.firebaserc` fait pointer l'alias **`production-next` sur le même
projet** `adfoot-production` — ce n'est pas une pré-production séparée, et
`firebase projects:list` ne connaît que trois projets. Un
`npm.cmd run functions:deploy:production-next` sans ces lignes aurait donc
redéployé la production avec `MIRROR_LEGACY_FOLLOW_ARRAYS` absent, c'est-à-dire
à son défaut de code, qui est le mirroring **actif** : les callables de suivi
auraient recommencé à écrire les tableaux. Et comme
`public_profiles_follow_cleanup_v1` porte désormais `completed: true`, le
backfill ne repasse plus : les tableaux se seraient remplis sans que rien ne le
signale.

Règle : **tout fichier d'environnement qui cible `adfoot-production` porte les
mêmes lignes.** Corrigé le 13 octobre dans les quatre fichiers concernés, les
deux réels (gitignorés, donc locaux à ce poste) et les deux `*.example`
suivis par git, qui sont le seul endroit où la connaissance survit à ce poste :

| Fichier | Suivi | État |
| --- | --- | --- |
| `functions/.env.production` | non | fermeture appliquée et déployée |
| `functions/.env.production-next` | non | aligné — même projet |
| `functions/.env.production.example` | **oui** | valeurs post-fermeture + le pourquoi |
| `functions/.env.production-next.example` | **oui** | les trois flags, qui manquaient entièrement |
| `functions/.env.staging` / `.example` | non / **oui** | alignés, pour que staging ne diverge pas dans la zone qui vient de changer |

Vérifié : `functions:env:check:production-next` et `functions:env:check:staging`
résolvent bien les deux valeurs. Après tout déploiement utilisant l'alias
`production-next`, repasser `npm.cmd run legacy:residue:gate:production`.

**Retour arrière.** Retirer les deux lignes et redéployer rétablit le
mirroring pour les écritures suivantes, mais **ne recrée pas** les tableaux
supprimés. C'est acceptable précisément parce qu'ils sont vides aujourd'hui ;
ce ne le serait plus après l'arrivée de vrais suivis. C'est la seule raison de
traiter cette fermeture maintenant plutôt qu'après le lancement.

Pour comparer en lecture seule le backend au contrat transitoire documenté
(**plus représentatif de la production depuis le 10 octobre**, à retirer avec
le fichier de règles transitoires) :

```powershell
npm.cmd run backend:parity:check:production:transition
```

Ce contrôle est limité à `adfoot-production` et compare Firestore à
`firestore.transition.rules`, Storage à `storage.rules`, ainsi que les index et
TTL. Le contrôle strict `npm.cmd run backend:parity:check:production` continue
de comparer Firestore à `firestore.rules` et doit réussir avant la fermeture de
la migration. Le mode transitoire ne donne aucun feu vert pour déployer les
règles finales ou fermer l'accès historique.

La version mobile déjà installée lit l'annuaire et les autres profils depuis
`users`. Le nouveau client lit `public_profiles`, tandis que les règles finales
de ce dépôt interdisent la lecture de `users/{autreUid}`. Ces règles finales ne
doivent donc pas être déployées directement pendant que l'ancienne version est
encore utilisée. Firestore ne sait pas masquer certains champs d'un document
aux anciens clients : la confidentialité totale des anciens `users` et leur
fonctionnement continu ne peuvent pas être obtenus simultanément par une seule
règle de lecture.

## Phase 1 — Préparer le backend additif

### Complément du 4 octobre 2026 : audiences des listes

Le candidat utilise `videos.publicFeedVisible` et `conversations.readableBy`.
Déployer aussi `syncVideoAudience` et les trois index correspondants ; vérifier
que le backfill v5 a effectivement rempli ces champs avant les tests internes.
Depuis le 5 octobre, son identifiant est `public_profiles_and_follows_v5` :
une ancienne complétion v4 ne fait pas ignorer cette nouvelle préparation.
Ne pas réutiliser les anciennes règles transitoires comme validation du candidat.
Les requêtes des anciens clients (flux sur `status` seul, boîte sur
`utilisateurIds`) sont incompatibles avec les nouvelles règles finales.
Valider le candidat complet sur un environnement de test isolé avant toute
bascule de production et trancher la fin de prise en charge des anciens clients.

1. Figer le SHA mobile/backend/admin et contrôler la parité staging puis
   production. Sauvegarder règles et index déployés avant tout changement.
2. Déployer les index nécessaires à `public_profiles` et aux conversations.
   Attendre leur état `READY`.
3. Déployer les Functions de projection et les backfills. La migration
   `public_profiles_and_follows_v5` repasse sur les profils déjà migrés afin
   de matérialiser `isMinorProfile` sur les comptes historiques, réindexer les
   projections et appliquer les protections mineurs. Ne pas déployer les
   règles finales ni publier le client qui filtre `isMinorProfile == false`
   avant `migration_state/public_profiles_and_follows_v5.completed=true` et
   avant d'avoir confirmé qu'aucun compte actif ne manque ce marqueur.
   Garder `ENABLE_LEGACY_CV_URL_MIGRATION` et
   `ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP` désactivés, et
   `MIRROR_LEGACY_FOLLOW_ARRAYS=true` : l'ancien client ouvre
   directement `cvUrl` et lit les tableaux de suivis. Les callables de suivi
   continuent temporairement à écrire ces tableaux en plus des relations.
4. Publier **des règles transitoires testées** qui autorisent à la fois la
   lecture historique de `users` par les comptes actifs et la lecture de
   `public_profiles` par le nouveau client. Ne pas déployer les règles finales
   `firestore.rules` à cette étape. Les autres contrôles de propriété et
   d'écriture du jeu final doivent rester en place. Cette étape maintient
   temporairement l'exposition des champs des profils historiques ; sa durée
   doit être réduite et suivie.
5. Attendre `migration_state/public_profiles_and_follows_v5.completed=true`
   et `migration_state/conversation_sort_dates_v1.completed=true`. Comparer le
   nombre de comptes actifs aux projections, puis vérifier des profils privés,
   profils publics, suivis, conversations vides, CV et profils désactivés.

## Phase 2 — Distribuer et mesurer

1. Installer l'ancien client et le nouveau client contre le même staging.
   Tester annuaire, profil, recherche, chat, suivi et suppression sur les deux.
2. Distribuer le nouveau client en internal test/TestFlight puis en production
   progressive. Surveiller Crashlytics, les erreurs `permission-denied`, la
   proportion des versions installées, les projections manquantes et les index.
3. Conserver la règle transitoire tant qu'une ancienne version supportée a
   besoin de `users`. Si une date d'arrêt est décidée, l'annoncer aux usagers
   et disposer d'un parcours de mise à jour utilisable avant de la bloquer.

## Phase 3 — Fermer l'ancien accès

1. Vérifier le seuil de migration des versions **avec des données réelles**.
   Le SHA, les nombres de comptes et la date de décision sont consignés dans le
   dossier de release. Un pourcentage seul ne suffit pas : compter aussi les
   appareils encore actifs sur l'ancien build.
2. Déployer les règles finales `firestore.rules` et les tester avec le nouveau
   client. Une ancienne version encore installée perdra sa lecture des autres
   profils ; traiter ce cas comme une rupture connue, jamais comme une
   transition transparente.
3. Activer `ENABLE_LEGACY_CV_URL_MIGRATION=true` seulement après la sortie des
   anciens clients : leurs boutons CV ne savent pas ouvrir les chemins `gs://`.
   Supprimer/faire tourner les anciennes URL de téléchargement divulguées.
   Activer ensuite `MIRROR_LEGACY_FOLLOW_ARRAYS=false` et
   `ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP=true` dans une release backend
   distincte après contrôle des relations. Attendre
   `migration_state/public_profiles_follow_cleanup_v1.completed=true`.
   Vérifier la parité des règles et les accès refusés, puis retirer
   la règle transitoire des artefacts de release.

**Arrêt de promotion :** profils invisibles, hausse des `permission-denied`,
index non prêts, backfill incomplet, suppression ou lecture CV incorrecte.
Aucun de ces déploiements n'est effectué par ce document.
