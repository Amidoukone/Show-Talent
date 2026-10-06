# Audit de cohérence — 6 octobre 2026

## Périmètre et corrections

Second passage sur le mobile Flutter Android/iOS, le portail admin, le site public,
les contrats partagés et les accès Firebase. Il complète la validation du 5 octobre.
Le candidat mobile devient **1.0.7+43** et remplace le bundle 42 pour les prochains tests.

- Recherche vidéo : une requête par auteur en échec remonte désormais à l'état
  d'erreur visible au lieu de donner des résultats partiels ou artificiellement vides.
  Le filtre `publicFeedVisible == true` et son index correspondent aux droits du flux public.
- Pagination des vidéos d'un profil : la fin se calcule sur le nombre de documents
  reçus, avant filtrage local des vidéos sans URL et déduplication. Un test couvre
  une première page de 20 documents non lisibles suivie d'une vidéo lisible.
- Portail : les erreurs de lecture des utilisateurs, des coordonnées et les profils
  invalides déclenchent un état explicite avec relance. La suppression d'une coordonnée
  privée efface également sa valeur affichée. Une page devenue hors limites après
  suppression est ramenée à une page valide.
- Site : les opérations Firebase de réinitialisation/vérification sont limitées à
  15 secondes et affichent une erreur explicite en cas de dépassement.
- Outillage : le contrôle du planificateur utilise l'environnement demandé ; les
  arguments du smoke test sont validés avant chargement des SDK Firebase ; les
  contrôles des fichiers servis incluent maintenant `auth-action.js`.
- Le test historique autorisant l'effacement de la date d'un joueur a été remplacé
  par un test de protection de la date obligatoire. La règle métier reste inchangée.

## Vérifications locales

| Contrôle | Résultat |
| --- | --- |
| Tests Flutter mobile | 962 réussis |
| Tests Flutter admin, suite entière | 115 réussis |
| Tests backend | 15 réussis |
| Tests Node : cible, encodage, authentification web | 4 réussis |
| Règles Firestore, émulateur | 100/100 |
| Règles Storage, émulateur | 30/30 |
| Analyse Flutter mobile et admin | Aucune anomalie |
| Contrat partagé admin/mobile, mode strict | Conforme |
| Encodage des sources déployables | 378 fichiers, aucune anomalie détectée |
| Traductions mobile | 819 clés FR et 819 EN, aucune clé manquante |
| Préparation iOS de production | Contrôles locaux réussis ; archive macOS restante |

Les tests de règles ont été exécutés le 5 octobre pendant ce passage ; les suites
complètes et les analyses finales ont été exécutées le 6 octobre. Les tests de release
admin sont un sous-ensemble des tests ci-dessus, pas des tests supplémentaires distincts.

Le scanner vérifie le décodage UTF-8 strict, les signatures usuelles de mojibake,
les caractères de remplacement/contrôle suspects et la syntaxe JSON/ARB. Il préserve
les accents légitimes. Il ne constitue pas une preuve sur tous les contenus saisis
par les utilisateurs ni sur le rendu de chaque écran sur appareil.

## Vérifications distantes

Staging : 44 index prêts, règles Firestore/Storage identiques au dépôt, deux TTL actifs.
Les parcours Firebase vérifient l'annuaire, les talents, leurs filtres, le flux vidéo,
les vidéos récentes, les vidéos par auteur, les vidéos d'un profil et la messagerie.
Les assertions positives sont complétées par des refus attendus d'accès aux mineurs
et d'écriture cliente sur les projections publiques. Les fixtures créées sont supprimées.
Ne pas interpréter les `PERMISSION_DENIED` de ces assertions négatives comme des échecs.

Le site et le portail de staging sont publiés : 9 fichiers comparés par SHA-256 et
4 routes vérifiées. Les pages juridiques en brouillon et les CV invalides renvoient 404.

Production : site public et portail corrigés publiés. Les 44 index sont `READY`, les
règles correspondent au dépôt et les deux TTL sont actifs. Le premier contrôle a
correctement refusé l'index encore `CREATING` ; le contrôle final est réussi.
Les mêmes parcours Firebase sont réussis, puis toutes leurs fixtures sont nettoyées.
Le contrôle final retrouve 3 utilisateurs, 3 projections, 0 vidéo et 0 conversation,
sans anomalie de cohérence ni écart de droits pour l'administrateur.
Les 15 fichiers servis sur les deux origines publiques et le portail sont identiques
aux fichiers locaux ; les quatre routes attendues sont conformes.

Le contrôle du nettoyage planifié signalait une dernière réussite du 4 octobre,
plus ancienne que son seuil de 30 heures. Inspection : tâche activée, statut sans
erreur, prochain passage prévu le 6 octobre à 09:57 UTC. Une exécution manuelle via
Cloud Scheduler a réussi le 6 octobre à **00:39:38 UTC**, sans modification de sa
politique de rétention. Le contrôle du planificateur est maintenant réussi et les
trois comptes présents ont été conservés. Le passage automatique suivant reste à
observer ; cette exécution manuelle ne prouve pas son déroulement futur.

Cloud Logging, fenêtre **00:30:00–00:43:21 UTC le 6 octobre** : aucune entrée de
sévérité `ERROR` ou supérieure sur les ressources Cloud Run/Functions consultées.
Ce résultat porte sur cette fenêtre et ces ressources, pas sur tous les appareils.

## Artefact Android

- Fichier : `artifacts/android/adfoot-production-20261006T003823Z.aab`
- Version : **1.0.7+43**, application `org.adfoot.app`, production, Play Integrity.
- Taille : **73 808 211 octets**.
- SHA-256 : `cc301e0b8af317457281d298c98514f40c5154e2459b2dea916b08f1f9d63772`.
- Compilation propre, signature vérifiée (`jar verified`), version et témoins Dart
  conformes ; snapshot Dart différent de celui du bundle 42 et postérieur aux sources.
- Bibliothèques natives 64 bits : alignement 16 KB conforme.

`jarsigner` conserve des avertissements sur le certificat autosigné, l'absence de
timestamp et les lectures différentes JarFile/JarInputStream de l'archive contenant
les symboles natifs. Son résultat positif ne remplace pas la validation de l'AAB
par Google Play. Le journal complet est conservé dans les preuves locales.

Le manifeste `artifacts/production-release-manifest-2026-10-06.json` consigne les
commits des deux dépôts et les empreintes des sources, du portail et du bundle.
Le manifeste du 5 octobre reste la référence historique du bundle 42.

## Preuves locales

Les journaux ignorés par Git sont conservés dans `artifacts/expert-*` :
`flutter-tests`, `flutter-analyze`, `admin-tests`, `admin-release-check`, `backend-tests`,
`node-tests`, `encoding`, `contract`, `ios-readiness`, `staging-parity`, `staging-smoke`
et `staging-hosting`, suffixés `2026-10-06` ; règles : `expert-rules-2026-10-05.log`.

## Limites avant publication dans les stores

Aucune revue ne permet d'affirmer l'absence absolue de bugs. Les résultats ci-dessus
portent sur les contrôles exécutés. Les tests physiques restent nécessaires pour :
connexion, vérification/réinitialisation, langue et accents, recherche et pagination,
upload/modération/lecture vidéo, notifications, liens profonds, messagerie et blocage,
permissions caméra/micro/photos, reprise réseau et arrière-plan.

La signature et les SDK iOS doivent être validés par une archive sur macOS puis
TestFlight. `Podfile.lock` n'est pas encore généré. Aucun IPA ni import TestFlight
n'est attesté par cette revue. L'import Play et l'acceptation du store restent également
à vérifier. Les avertissements de maintenance AGP/Kotlin et les avertissements de
dépendances de compilation ne sont pas assimilés à des erreurs applicatives silencieuses.
