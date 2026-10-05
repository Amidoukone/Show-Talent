# Transition sans rupture de `users` vers `public_profiles`

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

Pour comparer en lecture seule le backend au contrat transitoire documenté :

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
