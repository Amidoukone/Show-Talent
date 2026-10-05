# Production — candidat pour tests physiques du 5 octobre 2026

## Périmètre et décision

Déploiements production autorisés par le propriétaire du projet le 5 octobre. Les comptes présents sont des comptes de test. Ils ont été conservés et migrés ; aucune suppression générale n'a été faite.

Le backend et les interfaces web sont déployés. Le candidat Android est compilé. La validation finale sur appareils et l'acceptation des builds par Play/TestFlight restent à faire. Aucun envoi aux stores ni lancement de build distant iOS n'a été effectué depuis cette session.

## Déploiements et contrôles

| Élément | Résultat |
| --- | --- |
| Projet | `adfoot-production` |
| Cloud Functions | 58 créations/mises à jour réussies ; lint et compilation TypeScript réussis |
| Firestore | 43 index déclarés, 43 déployés et READY, aucun index supplémentaire |
| TTL | `client_logs/expireAt` et `video_action_logs/expireAt` ACTIVE |
| Règles Firestore/Storage | Déployées ; empreintes distantes identiques aux fichiers locaux |
| Migration profils | `public_profiles_and_follows_v5` terminée ; checkpoints précédents conservés |
| Données après recette | 3 utilisateurs, 3 projections publiques, 0 vidéo, 0 conversation, aucune incohérence |
| Site public | https://adfoot.org et https://adfoot-production.web.app |
| Portail admin | https://adfoot-admin.web.app |
| Contrôles admin | Configuration production, contrat mobile/admin, 30 tests release et analyse réussis |
| Droits admin distants | 1 compte avec signal admin ; custom claim présent, aucun écart |
| Compilation admin | Réussie ; bundle servi identique au fichier compilé |
| Tests backend/configuration | 15 tests réussis ; 1 test supplémentaire vérifie le refus des cibles/identifiants incohérents dans les outils de recette |
| Flutter mobile | Analyse sans problème et 959 tests réussis lors du passage final du 5 octobre |
| Règles sur émulateurs | 97 tests Firestore et 30 tests Storage réussis lors du passage staging, sur les mêmes règles |

Ordre suivi : sauvegarde des règles distantes, index, fonctions, migration et contrôle des données, règles et site public, administration, contrôle de parité et recette distante.

Une erreur DNS locale a interrompu le premier contrôle final ; la relance a réussi. Le compte de service opérationnel n'a pas l'accès Cloud Logging : le contrôle des journaux utilise le compte Firebase CLI déjà authentifié, sans modifier les droits IAM.

Cloud Logging : aucune entrée de sévérité ERROR ou supérieure pour Cloud Run/Functions du 5 octobre **10:02:00 à 10:08:19 UTC**. Ce contrôle porte sur cette fenêtre et les parcours exécutés, pas sur les futures utilisations.

Le premier passage Flutter a détecté un chemin de compte de service fixé dans le nouveau script de diagnostic. Le script utilise désormais `GOOGLE_APPLICATION_CREDENTIALS` ou l'authentification Firebase CLI. La suite complète a ensuite été relancée avec succès ; aucune modification du code Dart ni recompilation Android n'était nécessaire pour cette correction d'outillage.

## Révisions du candidat

Les deux dépôts utilisent la branche `release/production-device-tests-2026-10-05`, synchronisée sur GitHub pour préparer les builds distants. Le portail admin est figé au commit `1005d08`. La révision mobile/backend et les empreintes des artefacts sont consignées dans `artifacts/production-release-manifest-2026-10-05.json`. Les branches principales n'ont pas été fusionnées.

## Recette distante

`scripts/smoke-release-candidate.mjs` utilise une cible explicite et des identifiants de service appartenant au même projet. Il a créé puis supprimé un compte temporaire, deux profils adulte/mineur, une métadonnée vidéo et une conversation vide. Les champs calculés ont été produits par les fonctions réellement déployées.

Contrôles réussis : annuaire, recherche adulte/mineur habilitée, filtres football/âge, flux vidéo, vidéos récentes, messagerie, refus de recherche mineur pour un compte non habilité et refus d'écriture directe dans les projections publiques. Aucun courriel, message ou média réel n'a été envoyé.

`scripts/check-production-hosting.mjs` compare les empreintes SHA-256 des pages publiques, de la confidentialité, de la suppression de compte et des fichiers d'association Android/iOS sur les deux domaines publics, puis de `index.html`, `main.dart.js` et `flutter_bootstrap.js` sur le portail admin. Les 13 comparaisons ont réussi. Les routes de réinitialisation et de vérification répondent ; un CV inexistant et les brouillons juridiques restent inaccessibles.

Les refus PERMISSION_DENIED présents dans le journal de recette sont des assertions attendues et vérifiées, pas un échec de la recette.

## Android à importer dans Play Console

- Package : `org.adfoot.app` (production).
- Version : `1.0.7+42`.
- Artefact : `artifacts/android/adfoot-production-20261005T100321Z.aab`.
- Taille : 73 807 089 octets.
- SHA-256 : `33d71827a84a55c4aa68e8d1411a4b05bb0e81e68b5fc9956b7c4278c2898a21`.
- Contenu Dart : empreinte différente de la précédente release, marqueurs attendus présents, compilation postérieure aux sources.
- Signature : `jarsigner` retourne `jar verified`. Il signale également le certificat autosigné, l'absence d'horodatage et les différences de lecture du manifeste entre JarFile/JarInputStream. L'acceptation effective par Play reste à confirmer à l'import.
- Alignement : 16 bibliothèques 64 bits vérifiées à 16 Ko minimum ; ARM 32/64 bits et x86_64 présents.
- Compilation avec signature release requise et contrôle Play Integrity activé.

Importer cet AAB dans la piste **test interne de l'application de production**. Installer ensuite depuis le lien des testeurs Play. L'AAB n'est pas un APK installable directement. Vérifier que le code 42 n'a pas déjà été consommé sur Play ; aucun accès à l'état des pistes Play n'a été utilisé dans cette session.

## iOS à compiler sur Codemagic

- Workflow : `ios-production`, scheme `production`, bundle `org.adfoot.app`.
- Groupes : `appstore_credentials` et `firebase_ios_production` ; intégration `adfoot_app_store_connect`.
- Domaine de partage rendu explicite : `https://adfoot.org`.
- Nouveau contrôle `node scripts/check-ios-build-env.mjs production` dans le workflow : environnement, projet, bundle, App ID iOS, sender, bucket et domaine doivent correspondre.
- Contrôles locaux de configuration et de préparation iOS réussis. Firebase Auth Email/Password répond avec la configuration iOS production.
- `Podfile.lock` absent : installation CocoaPods nécessaire sur le runner Mac.
- Le workflow prévoit TestFlight, sans soumission App Store. Aucun IPA n'a encore été produit ou vérifié pendant cette session ; les secrets et certificats distants Codemagic ne sont pas inspectables ici.

Lancer le workflow sur la révision synchronisée du candidat, pas sur une ancienne branche. Vérifier ensuite la signature de l'IPA, son traitement dans App Store Connect et l'installation TestFlight sur iPhone.

## Recette physique à consigner

| Parcours | Android | iPhone |
| --- | --- | --- |
| Installation depuis Play interne / TestFlight ; version 1.0.7 (42) | À faire | À faire |
| Connexion, déconnexion, invitation et réinitialisation | À faire | À faire |
| Recherche adulte/mineur suivant les droits du compte | À faire | À faire |
| Création et modification d'un joueur depuis l'administration, résultat dans le mobile | À faire | À faire |
| Consentement, autorisation média, retrait et protection du profil mineur | À faire | À faire |
| Envoi/lecture vidéo, modération et retrait depuis l'administration | À faire | À faire |
| Conversation, notifications en premier plan et arrière-plan | À faire | À faire |
| CV et liens partagés, ouverture dans le navigateur et dans l'application | À faire | À faire |
| Reprise après perte réseau et redémarrage de l'application | À faire | À faire |

Installer le nouveau candidat sur les appareils de test : les anciennes versions peuvent utiliser des requêtes incompatibles avec les nouvelles règles. La mise en cohérence production ne constitue pas une preuve de compatibilité de ces anciennes versions.

Les brouillons juridiques restent exclus de l'hébergement. Fermer une page de partage ne révoque pas les anciennes URL Firebase de téléchargement ni les copies déjà téléchargées.

## Preuves locales

Les journaux sont dans `artifacts/production-*-2026-10-05.*` : déploiements, migration avant/après, parité finale, recette, vérification des sites, build Android, signature, alignement, contrôles Auth iOS et résultats Flutter. Les anciennes règles sont sauvegardées dans `artifacts/deployed-rules/adfoot-production/` ; elles constituent un historique, pas un retour arrière automatique compatible avec les nouveaux profils.
