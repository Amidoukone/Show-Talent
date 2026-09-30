# Audit global Adfoot — état local du 28 septembre 2026

## Périmètre et niveau de preuve

Audit du checkout `1.0.7+42`, avec les nombreuses corrections locales **non commitées** présentes au moment de la revue. Lecture du client Flutter, des règles Firestore et Storage, des Functions, des configurations natives, de la CI, des scripts de release et des pages légales. Aucun déploiement, build signé, changement de configuration distante ni écriture en production n'a été effectué. Un test réussi sur iPhone 12 et les tests internes Android prouvent des parcours réels utiles, mais ne prouvent pas la conformité de l'IPA/AAB final ni la parité du backend déployé.

### Contrôles exécutés sur cet état local

| Contrôle | Résultat |
| --- | --- |
| `flutter analyze --no-pub` | Réussi, 0 problème. |
| `flutter test --no-pub` | Réussi, 954 tests. Des tests `guardrails` inspectent du texte source ; ils ne remplacent pas un test d'intégration. |
| Functions `npm run lint`, `npm run build`, `npm test` | Réussis ; 5 tests CV et projection. La CI lance maintenant ces tests. |
| `release:ios:check` | Réussi ; avertissement `Podfile.lock` absent sous Windows. Le script ne vérifie ni l'IPA signé ni la liaison effective des entitlements. |
| `release:android:check`, `release:android:check:playstore` | Réussis ; le second exige Play Integrity. Aucun AAB final inspecté. |
| `security:secrets:check`, `contract:admin-mobile:check`, `git diff --check` | Réussis. Le contrôle de contrat compare le dépôt admin frère local. |
| `npm audit --omit=dev --audit-level=high` | 0 high/critical ; 8 avis modérés dans la racine, 2 dans `functions`. Cela ne démontre pas l'exploitabilité. |

Le document `audit-remediation-2026-09-27.md` rapporte 67 tests Firestore et 25 tests Storage réussis sur émulateur. Ils n'ont pas été relancés dans cette revue. La parité production, les comptes Apple/Google, les clés APNs, la signature et les autorisations de personnes photographiées ne sont pas vérifiables depuis ce seul checkout.

## Décisions bloquantes avant promotion

### R1 — Transition des anciens clients incompatible avec le verrouillage de `users` (critique à la mise en service)

Le client actuellement à `HEAD` lit les autres personnes et l'annuaire depuis `users` (`git show HEAD:lib/services/users/user_repository.dart`, méthodes `watchAllUsers` et `fetchUserById`). Les règles locales nouvelles donnent `read` sur `users/{uid}` seulement au propriétaire/admin (`firestore.rules:611-625`) ; le nouveau client lit `public_profiles` (`lib/services/users/user_repository.dart:74`). Le runbook actuel impose pourtant les règles avant le nouveau mobile (`CLAUDE.md`, « Ordre obligatoire »). Ce déploiement couperait les lectures de profils des clients déjà installés. Inversement, publier le nouveau client avant le remplissage de `public_profiles` peut afficher des annuaires vides. Le backfill actuel ne traite que 200 utilisateurs par exécution horaire (`functions/src/cleanup.ts:204-252`).

**Action :** appliquer le plan `docs/checklists/public-profile-rollout-2026-09-28.md` et mesurer les versions actives. Préparer les index et Functions, remplir et compter les projections/relations, tester ancien et nouveau clients en staging contre des règles transitoires, puis ne fermer l'ancienne lecture qu'après le seuil de migration décidé. Les anciens clients lisent aussi les tableaux de suivi et ouvrent directement les URL de CV : leur suppression/conversion est maintenant différée par deux options désactivées par défaut. Une bascule immédiate des règles finales interrompt néanmoins les anciennes versions ; ne pas la présenter comme une migration transparente.

### R2 — Notifications iOS de production non démontrées (élevé)

`ios/Runner/Runner.entitlements:5-6` contient `aps-environment=development`. **Correction de l'audit initial :** les fichiers `ios/Flutter/Debug.xcconfig` et `Release.xcconfig` définissent déjà `CODE_SIGN_ENTITLEMENTS=Runner/Runner.entitlements` ; les configurations de saveur les incluent. Apple indique que Xcode règle l'environnement APNs selon le profil de signature, donc la valeur du fichier source ne prouve pas une erreur de l'IPA. Le préflight (`scripts/check-ios-release-readiness.ps1:182-207`) vérifie la configuration source, mais pas la valeur dans le binaire signé. Le chemin iOS au premier plan est explicite (`lib/services/notifications.dart:40-47`) ; la livraison APNs production reste à démontrer sur TestFlight.

**Action :** le contrôle `scripts/verify-ios-ipa.sh` est désormais appelé par les workflows Codemagic après le build et avant l'envoi. Il vérifie la signature, le bundle ID, `aps-environment=production` et le domaine associé de l'IPA exporté. Confirmer la clé APNs dans Firebase, puis tester réception et ouverture en avant-plan, arrière-plan et application fermée sur un build TestFlight **production**. Ce contrôle ne remplace pas un test sur appareil réel.

### R3 — Droits sur les images et modèle publicitaire à décider avant création des visuels (élevé)

La politique locale décrit les traitements nécessaires au service (`site_pub/legal/privacy-policy.html`) mais ne décrit pas une finalité promotionnelle spécifique. Aucun SDK publicitaire n'est déclaré dans `pubspec.yaml` ; les publicités prévues peuvent donc être des créations internes, des campagnes externes ou une future fonctionnalité. Ces scénarios impliquent des déclarations et des contrôles différents. Les catégories `U17` et `U19` restent proposées dans le vocabulaire des offres (`lib/models/football_vocabulary.dart:155-160`) alors que les CGU et l'écran d'acceptation réservent l'utilisation aux adultes (`lib/screens/terms_acceptance_screen.dart:45-50`). Cette tension doit être tranchée avant de choisir des joueurs pour les visuels.

**Action :** constituer pour chaque image/vidéo la preuve d'autorisation du joueur, du photographe et des éventuels ayants droit (club, maillot, logo), avec usages précis : app, campagne externe, capture store, territoires, durée et retrait. Éviter les profils réels dans les captures si possible. Faire examiner séparément toute image d'un mineur. Définir si les offres U17 servent des clubs sans inscription de joueurs mineurs ou si elles doivent être cachées. Si des annonces ou SDK de mesure entrent dans l'app, revoir avant soumission App Privacy, Data safety, consentements et politique publiée. Apple exige les droits sur les éléments des captures et recommande des comptes fictifs ; ses règles UGC exigent modération, signalement, blocage et contact ([App Review Guidelines 1.2 et 2.3.9](https://developer.apple.com/app-store/review/guidelines/)). Les réponses App Privacy doivent inclure les partenaires intégrés et rester à jour ([App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)).

## Risques encore présents dans le code

| Priorité | Constat et preuve | Effet / vérification attendue |
| --- | --- | --- |
| P2, partiellement corrigé | La projection est maintenant ignorée quand seule la présence dans le chat change (`functions/src/public_profile_projection.ts`). Un changement public lance encore une transaction et une écriture de projection. | Mesurer écritures/latence Functions sous charge ; envisager une comparaison avec la projection stockée si le coût reste élevé. |
| P2, partiellement corrigé | L'index conserve maintenant chaque terme complet, puis distribue les préfixes courts sur les champs (`functions/src/public_profile_projection.ts`). Le plafond global reste de 200. | Tester des profils extrêmes et la qualité des requêtes partielles après le backfill v3 ; prévoir un vrai moteur de recherche si le volume le justifie. |
| P2 | La recherche de vidéos par texte retombe sur un balayage d'un nombre limité de vidéos récentes lorsque les auteurs indexés ne donnent rien (`lib/screens/home_screen.dart:582-607`) ; `fetchRecentReadyVideos` applique une limite (`lib/services/home/home_feed_repository.dart:88-97`). | Les vidéos anciennes correspondant au texte peuvent rester introuvables. Documenter la portée réelle de la recherche ou indexer les métadonnées vidéo avec pagination. |
| P2 | La file de fanout envoie avant d'enregistrer le curseur (`functions/src/fanout_campaigns.ts:60-145`). Une interruption entre FCM et l'update rejoue la page ; le document de remédiation reconnaît cette livraison au moins une fois. | Notifications en double possibles ; ajouter un identifiant de campagne côté payload/client et une mesure des relectures, ou des reçus par page si le volume le justifie. |
| P2, corrigé localement | `sendUserPush` refuse désormais les envois directs d'offres/événements ; seules les campagnes dédiées portent ces contenus (`functions/src/actions.ts`). | Vérifier sur staging qu'aucun ancien client ne dépendait de ce chemin et que les campagnes dédiées arrivent correctement. |
| P3 | Le client n'a que `fr` et `en` (`lib/l10n/app_fr.arb`, `app_en.arb`) malgré l'audience africaine/internationale. | Décision produit : valider la qualité des termes footballistiques, pays, postes, âges et niveaux sur les marchés de lancement ; relever les écrans encore en texte fixe avant extension linguistique. |

## Points désormais solides, sous réserve de déploiement

- La projection `public_profiles` limite la lecture intercomptes, le jeton FCM vit dans `user_push_tokens`, les CV récents utilisent un chemin `gs://` et un lien court contrôlé (`firestore.rules:611-681`, `functions/src/public_profile_projection.ts`, `functions/src/cv_view.ts`). La conversion des anciennes URL est désactivée pendant la transition des clients ; vérifier les anciens documents et les anciennes URL diffusées après la fermeture de l'accès historique.
- La suppression client directe du profil est refusée ; le callable a une reprise pour l'échec Auth (`firestore.rules:625`, `functions/src/account_deletion_actions.ts`, `functions/src/cleanup.ts`). Tester une panne injectée et la suppression complète de toutes les collections/objets.
- Les demandes de contact exigent la mise à jour atomique du quota (`firestore.rules:845-885`). Le push de message vérifie auteur, destinataire, âge du message, blocage et reçu anti répétition (`functions/src/actions.ts:609-830`).
- La recherche de talents et les conversations sont paginées ; les suivis migrent vers des relations ; le feed vidéo possède des contrôles de chargement et de lecture. Vérifier les index **déployés** et les migrations avant de considérer cette couverture effective.
- Les permissions média Android larges ont été retirées du manifeste source, les catégories de données iOS ont été renseignées, et les gates locaux passent. Vérifier le manifeste fusionné de l'AAB et les déclarations réellement enregistrées dans les consoles.

## Plan de validation final, dans l'ordre

1. **Figement vérifiable :** commiter les corrections après revue, noter SHA, versions, schémas/index, IDs Firebase, versions des pages légales et état du portail admin. Sauvegarder un rollback du backend et un tableau de compatibilité ancien/nouveau client.
2. **Staging avec données représentatives :** plus de 200 profils et conversations, profil privé/public, CV révoqué, blocage, âge 17/18, offre U17, interruption du fanout, suppression Auth échouée, migration partielle. Comparer les comptes et relations avant/après backfill ; lire les erreurs Functions et Firestore.
3. **Intégration réelle :** tests de règles sur l'émulateur au SHA final, tests comportementaux des callables sensibles, puis Android internal test et iOS production TestFlight avec les **artefacts signés**. Vérifier APNs, app/universal links, CV PDF/Range, upload vidéo, traitement/transcodage, feed, recherche, candidatures, événements, chat, signalement et blocage.
4. **Stores et exploitation :** contrôler AAB/IPA finaux, Data safety/App Privacy, comptes de démonstration, pages légales réellement publiées, droits des visuels, processus de modération, Crashlytics, coûts Firebase et alarmes sur fonctions/queues. Google examine les permissions du bundle soumis lors de la release ([Play Console](https://support.google.com/googleplay/android-developer/answer/9214102?hl=en)).
5. **Promotion progressive :** préparer la compatibilité des anciennes versions avant de verrouiller `users`, suivre `permission-denied`, taux de profils visibles, latence du feed, échecs d'upload, campagnes et notifications ; arrêter la promotion si un seuil défini est dépassé.

**Avis :** le code local est nettement plus proche d'une release, mais l'état actuel ne permet pas de prononcer un feu vert final. Les trois décisions R1–R3 et la preuve sur les artefacts signés, le backend déployé et les droits des images sont nécessaires avant publication générale.
