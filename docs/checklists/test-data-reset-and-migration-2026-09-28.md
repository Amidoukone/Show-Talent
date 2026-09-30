# Remise à zéro des données de test et migration v3 — 28 septembre 2026

## Périmètre autorisé

Le propriétaire du projet a autorisé la suppression des comptes et contenus de
test sur `adfoot-staging`, puis `adfoot-production`. À conserver : tous les
comptes opérateurs admin, `amidoudev@gmail.com`,
`amidou.kone.pro@gmail.com`, les profils de ces comptes, leurs fichiers
personnels et la configuration de l'application.

## Exécution

| Projet | Auth avant → après | Claims admin après | Profils attendus / présents | Contenu et médias de test après |
| --- | ---: | ---: | ---: | --- |
| staging | 8 → 7 | 5 | 6 / 6 | Vidéos, miniatures, offres, événements et journaux : 0 |
| production | 18 → 3 | 1 | 3 / 3 | Vidéos, miniatures, offres, événements et journaux : 0 |

`config` en production : 1 document avant et après. Les photos/CV des comptes
protégés restent dans Storage. Les relations de suivi de tous les comptes
protégés ont été remises à zéro pour éviter des références vers les comptes
supprimés. Les autres collections de données de test ont été supprimées
récursivement. Les sauvegardes locales ignorées par Git sont :

- `artifacts/reset-backups/adfoot-staging-2026-09-28T18-55-12.756Z/`
  (20 fichiers, 20 617 639 octets) ;
- `artifacts/reset-backups/adfoot-production-2026-09-28T19-01-18.746Z/`
  (44 fichiers, 268 544 074 octets).

Les sauvegardes contiennent des documents Firestore sérialisés et les médias
effacés. Elles servent à l'audit ou à une restauration manuelle ; elles ne
constituent pas un export Firebase Auth des mots de passe ni un outil de
restauration automatique. Garder ces dossiers hors Git et les supprimer selon
la politique de conservation décidée pour les tests.

Les 31 index déclarés sont `READY` dans les deux projets. Les deux Functions
`backfillPublicProfiles` et `syncPublicProfileOnUserWrite` ont été mises à jour
sur staging puis production. Le backfill v3 a été achevé avec
`migration_state/public_profiles_and_follows_v3.completed=true` dans chaque
projet. Contrôle final : aucune projection manquante ni orpheline.

## Règles transitoires de production

Les règles Firestore et Storage de staging correspondent au checkout local.
Un jeu `firestore.transition.rules` a été construit à partir des règles
Firestore précédemment déployées en production. Il conserve la lecture
historique de `users` et ajoute `public_profiles`, les relations de suivi et
les blocs directionnels ; un blocage empêche aussi les nouveaux messages.
Les cas ancien/nouveau client ont réussi sur l'émulateur Firestore. Le jeu a
été déployé en production et la copie récupérée par l'API Rules est identique
octet pour octet au fichier testé. Les règles Storage de production n'ont pas
été modifiées lors de cette étape. Elles ont ensuite été alignées sur
`storage.rules` ; le seul écart était l'accès aux claims admin avec `get`.
Les 25 tests Storage et les 67 tests des règles Firestore finales locales ont
réussi. Les règles Storage de production récupérées après déploiement sont
identiques à `storage.rules` ; les règles Firestore récupérées sont identiques
à `firestore.transition.rules`.

**Reste à faire pour la release :** ne pas publier directement les règles
finales locales tant que les anciens builds Android lisent
`users/{autreUid}` : ils perdraient l'annuaire et les profils. Suivre
`public-profile-rollout-2026-09-28.md` : tests sur ancien et nouveau binaires,
mesure des versions actives, puis fermeture de l'accès historique. Pendant la
transition, les anciens clients gardent l'accès aux documents `users` complets,
avec la confidentialité historique correspondante. Les corrections de sécurité
plus strictes des règles finales restent à promouvoir au terme de ce passage.
La migration des données v3 n'est pas une preuve des binaires signés.

## Commandes de vérification

```powershell
node scripts/inventory-test-data.mjs --project adfoot-staging --service-account .credentials/adfoot-staging-firebase-adminsdk-fbsvc-65ed95b460.json
node scripts/inventory-test-data.mjs --project adfoot-production --service-account .credentials/adfoot-production-ops.json
node scripts/check-deployed-firestore-indexes.mjs --environment production --credentials .credentials/adfoot-production-ops.json
node scripts/check-deployed-firebase-rules.mjs --environment production --credentials .credentials/adfoot-production-ops.json
```
