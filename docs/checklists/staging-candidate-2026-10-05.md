# Candidat staging — 5 octobre 2026

## État

Le backend, les règles, les index, le portail admin et le site public staging ont été déployés. La recette automatisée sur ce staging passe. Aucun déploiement en production ni envoi aux stores n'a été effectué.

- Site : https://adfoot-staging.web.app
- Administration : https://adfoot-admin-staging.web.app
- Projet Firebase : `adfoot-staging`.
- Version mobile : `1.0.7+42`.
- Base Git : `fbd94bd`, branche `fix/audit-remediation-pre-release-2026-09` ; les modifications locales ne sont pas encore synchronisées avec le dépôt distant. Ce commit seul ne reproduit donc pas le candidat.

## Corrections de cette étape

- Migration `public_profiles_and_follows_v5` : recalcul des champs de recherche/âge avant projection publique et synchronisation des audiences. Le checkpoint v4 reste conservé.
- Script `prepare-staging-candidate.mjs` limité au projet staging : migration explicite avec `--apply`, contrôle en lecture seule par défaut.
- Correction des App IDs Firebase iOS et Web dans la configuration staging locale ; le contrôle compare maintenant les identifiants aux configurations natives et vérifie leur plateforme.
- Correction d'un identifiant Web factice dans la configuration production locale ignorée par Git, depuis la configuration Firebase récupérée en lecture seule. Aucune modification distante de production.
- Workflow iOS staging : domaine de partage staging explicite et validation de la configuration avant compilation, avec tests de rejet des configurations incohérentes.
- Diagnostic des index : la commande suggérée utilise désormais le projet réellement contrôlé.

## Vérifications réalisées

| Contrôle | Résultat |
| --- | --- |
| Index staging | 43 index attendus, tous READY |
| Règles Firestore et Storage staging | Empreintes déployées identiques aux fichiers locaux |
| Migration v5 | Terminée ; aucune incohérence détectée |
| Tests Firestore sur émulateur | 97 réussis |
| Tests Storage sur émulateur | 30 réussis |
| Tests backend et configuration iOS | 14 réussis |
| Build admin staging | Réussi et déployé |
| Build Android staging signé | Réussi |
| Alignement natif Android | 16 bibliothèques 64 bits conformes au seuil 16 Ko ; ABI ARM 32/64 bits et x86_64 présentes |
| Contrôles de configuration Android/iOS | Réussis ; compilation iOS non réalisée |

La recette `smoke-staging-candidate.mjs` a créé puis supprimé ses propres données temporaires : un compte de test, deux talents adulte/mineur, une métadonnée vidéo et une conversation vide. Elle a vérifié les projections produites par les fonctions déployées, les requêtes annuaire/recherche filtrée/flux/messagerie, le refus d'accès aux mineurs pour un compte non habilité et le refus d'écriture directe des projections publiques. Aucun message ni média réel envoyé.

Les pages publiques, la réinitialisation, la confidentialité et l'administration répondent ; les brouillons juridiques et un CV inexistant restent inaccessibles. Les avertissements PERMISSION_DENIED dans le journal correspondent aux refus attendus.

Après nettoyage, contrôle en lecture seule : **7 utilisateurs, 6 projections publiques, 0 vidéo, 0 conversation, aucune anomalie**.

Les 959 tests Flutter et l'analyse Flutter sans erreur datent du passage précédent du 4 octobre, détaillé dans `pre-internal-validation-2026-10-04.md`.

## Artefact Android

- Fichier : `artifacts/android/adfoot-staging-20261005T042600Z.aab`
- Package : `org.adfoot.app.staging`
- Taille : 73 807 522 octets.
- SHA-256 : `b3cf93effb385269c81954e204784c4f405bdfc0ef7a49839cf68d44981dfbc6`
- Version : `1.0.7`, code `42`, min SDK `24`, target SDK `36`.
- Vérification `jarsigner` : `jar verified`, avec avertissements certificat autosigné, absence d'horodatage et différence de lecture du manifeste entre JarFile/JarInputStream. L'acceptation par Play reste à vérifier lors de l'import.

Ce package staging nécessite une application Play correspondante ; il ne correspond pas à l'application de production. Aucun import Play n'a été effectué.

## Suite nécessaire avant validation finale

1. Synchroniser une révision précise contenant les corrections locales avant de lancer un build distant. Les configurations locales ignorées par Git doivent être reportées dans les variables CI appropriées.
2. Sur Codemagic, vérifier le groupe `firebase_ios_staging`, le bundle `org.adfoot.app.staging`, la signature et l'application App Store Connect correspondante ; lancer `ios-staging` sur cette révision. Aucun accès API Codemagic n'est disponible dans cette session. Aucun IPA ni TestFlight n'est encore validé.
3. Importer l'AAB dans l'application Play staging correspondante et vérifier l'acceptation du bundle et de sa signature.
4. Faire une recette sur appareils Android et iOS : connexion, réinitialisation, recherche adulte/mineur selon les rôles, modification de profil, vidéo et modération, messagerie, notifications, liens partagés, CV, consentement et retrait depuis l'administration, puis vérifier les résultats dans le mobile.
5. Conserver les preuves de cette recette et traiter les éventuelles erreurs avant décision de sortie en production.

Le plan de migration de production doit encore traiter les anciennes requêtes mobiles face aux nouvelles règles et audiences. La parité staging ne vaut pas validation de cette transition. Les brouillons juridiques ne sont pas publiés ; la fermeture d'une page de partage ne révoque pas les anciennes URL de téléchargement Firebase ni les copies déjà téléchargées.

## Journaux locaux

Dans `artifacts/` : `staging-migration-tests-2026-10-05.log`, `staging-indexes-deploy-2026-10-05.log`, `staging-functions-deploy-2026-10-05.log`, `staging-rules-site-deploy-2026-10-05.log`, `staging-admin-build-2026-10-05.log`, `staging-admin-deploy-2026-10-05.log`, `staging-parity-final-2026-10-05.log`, `staging-android-build-2026-10-05.log`, `staging-smoke-2026-10-05.log`.
