# Audit global Adfoot avant publication — 25 septembre 2026

## Portée et méthode

Revue du checkout local `1.0.7+42` : Flutter/Dart, règles Firestore et Storage, Cloud Functions, Android, iOS, CI, scripts de release, pages légales et dépendances Node. Les constats ci-dessous décrivent **le code présent dans ce dépôt**. La parité avec `adfoot-production`, les paramètres Firebase/Apple/Google distants, le contenu d'un IPA/AAB final, la charge réelle et les autorisations d'image n'ont pas été vérifiés à distance. Le test déjà effectué par l'équipe sur iPhone 12 reste une preuve fonctionnelle utile, sans couvrir à lui seul les cas de charge, d'abus ou la signature finale.

Le dépôt contient déjà des protections solides : variantes d'environnement, préflights Android/iOS, App Check tolérant aux appareils sans attestation, contrôle des rôles dans les callables sensibles, règles fermées par défaut, quotas d'upload, modération vidéo, rapports Crashlytics, pages de retry au démarrage et un grand jeu de tests Flutter. La pagination du feed vidéo et de l'historique des messages est présente.

### Validation exécutée

| Contrôle | Résultat local |
|---|---|
| `flutter analyze --no-pub` | Réussi, aucun problème. |
| `flutter test --no-pub` | Réussi, 950 tests. |
| `functions`: `npm run lint`, `npm run build` | Réussis. Pas de script `test` dans `functions/package.json`. |
| `release:ios:check` | Réussi avec avertissements sur `Podfile.lock` absent sous Windows et `aps-environment` absent. |
| `release:android:check`, `security:secrets:check` | Réussis. Le contrôle Android n'a pas exigé Play Integrity (`Require Play Integrity: False`). |
| `rules:test:all` | **Non validé localement** : la CLI Firebase s'est arrêtée avant le lancement de l'émulateur (`Timed out` dans `firebase-debug.log`). Ce poste utilise Java 17 ; le job CI prépare Java 21. |
| `npm audit --omit=dev --audit-level=high` | Échec : 11 avis dans la racine (dont 1 high et 1 critical), 15 dans `functions` (dont 2 high). Les avis ne prouvent pas que chaque chemin vulnérable est atteignable par un utilisateur. |

## Constats prioritaires

### P1 — Confidentialité des fiches privées non garantie par les règles

`firestore.rules:617-638` autorise tout compte actif à lire **tous** les documents `users/{uid}`, même si `profilePublic == false` ou si le compte cible est désactivé. Le code l'explique lui-même. `lib/services/users/user_repository.dart:437` stocke le jeton FCM dans ce document. Les champs privés `email`, `phone` et `birthDate` ont bien été déplacés vers `private/contact`, mais les autres données du document (profil, `cvUrl`, jeton FCM, données sociales et état de compte) restent énumérables par un compte actif. Plus grave, `lib/services/users/profile_repository.dart:762-771` stocke dans `cvUrl` une URL de téléchargement Firebase du PDF. Une URL de téléchargement est conçue pour être partageable ; Firebase recommande le téléchargement direct par SDK lorsqu'un contrôle fin par règles est requis ([Firebase](https://firebase.google.com/docs/storage/web/download-files)). La règle Storage qui protège `cvs/{uid}` n'est donc pas une protection suffisante si cette URL est exposée. La restriction d'écran ne constitue pas une restriction d'accès aux données.

**Action :** retirer le jeton FCM et l'URL du CV de toute projection lisible par des tiers ; stocker le chemin Storage du CV côté privé et télécharger par le SDK après contrôle d'accès, ou émettre des liens de courte durée côté serveur. Définir précisément ce qui doit être visible, créer une projection de profil consultable séparée et mettre le document complet sous une règle propriétaire/admin. Migrer les lectures mobiles et le portail admin avec une période de compatibilité. Ajouter des tests de règles montrant qu'un compte tiers ne lit pas un profil privé ni son jeton FCM. Examiner la rotation des URL de CV déjà divulguées. Vérifier les données historiques et les règles **déployées** avant de déclarer la confidentialité effective.

### P1 — Suppression directe du profil contourne la procédure de suppression de compte

`firestore.rules:647` accorde `delete` sur `users/{userId}` à son propriétaire. La suppression normale passe pourtant par `deleteOwnAccount` (`functions/src/account_deletion_actions.ts:64-132`), vérifie une authentification récente et nettoie vidéos, conversations, suivis et Auth. Un client modifié peut supprimer seulement le parent Firestore, sans cette vérification ni cascade. Firestore ne supprime pas automatiquement ses sous-collections lorsqu'on efface le parent ([documentation Firebase](https://firebase.google.com/docs/firestore/data-model)). Il peut rester un utilisateur Auth et des données orphelines, alors que l'app considère le profil absent comme un compte fermé.

**Action :** refuser `delete` client sur `users` et `users/{uid}/private/*`, puis garder la suppression côté serveur. Tester la tentative directe par l'émulateur et un parcours complet de suppression avec contrôle des données restantes.

### P1 — Une suppression partielle peut être annoncée comme terminée

Dans `functions/src/account_deletion_actions.ts:109-129`, si `auth.deleteUser()` échoue après `purgeAccountData()`, le callable renvoie `success: true`, `authDeleted: false`. Le client `lib/services/account_cleanup_service.dart:76-118` ne lit pas ce drapeau et déconnecte l'utilisateur comme si tout était terminé. Le commentaire serveur dit que `cleanupUnverifiedUsers` pourra retirer l'Auth orphelin, mais `functions/src/cleanup.ts:141-144` **ignore explicitement les comptes Auth vérifiés**. L'orphelin d'un compte vérifié peut donc persister sans reprise automatique.

**Action :** créer une tâche de reprise durable/alerte pour chaque échec Auth, rendre la suppression idempotente et faire confirmer l'état final au client. Tester une panne injectée de `auth.deleteUser()` puis la reprise. Garder une preuve de fin de suppression par identifiant, sans donnée personnelle dans le journal.

### P1 — Limite de fréquence des demandes de contact contournable

`firestore.rules:851-882` lit la valeur **précédente** de `contact_intake_limits/{uid}` et autorise la création d'une demande si elle est absente ou ancienne. Le client normal écrit ensuite cette limite dans le même batch (`lib/services/chat/chat_repository.dart:361-385`), mais la règle `contact_intakes` n'impose pas que cette écriture accompagne la création. Un client modifié peut omettre l'écriture de limite et créer des demandes répétées ; le trigger `functions/src/contact_intake_notifications.ts:96-204` peut alors générer des e-mails d'exploitation. La règle ne vérifie pas non plus l'existence de la cible ni une longueur maximale des textes.

**Action :** imposer le nouvel état via `getAfter()` dans la règle de création, ou déplacer la création vers un callable transactionnel avec quota serveur. `getAfter()` est le mécanisme prévu pour exiger des écritures liées dans un batch ([documentation Firebase](https://firebase.google.com/docs/firestore/security/rules-conditions)). Ajouter un test « création sans mise à jour de la limite refusée » et un test de deux créations rapprochées.

### P1 — Notifications directes possibles sans message et malgré un blocage

`functions/src/actions.ts:609-647` autorise `sendUserPush` pour une conversation dès que l'expéditeur et le destinataire figurent dans `utilisateurIds`. Aucun message correspondant, blocage réciproque ou état actif du destinataire n'est vérifié. Les règles Firestore bloquent bien **l'écriture d'un nouveau message** entre utilisateurs bloqués (`firestore.rules:781-801`), mais l'ancien membre de la conversation peut appeler le push directement avec un titre/corps arbitraire. Le plafond de 30 appels/minute (`actions.ts:90-93, 808-815`) limite le volume sans empêcher ce contournement.

**Action :** faire émettre le push depuis un événement de message validé ou vérifier côté serveur l'existence et l'auteur d'un message récent, le blocage et le compte actif. Ajouter un test de callable après blocage.

### P1 — Push iOS non prêt dans la configuration du dépôt

`ios/Runner/Runner.entitlements` ne contient que `applinks:adfoot.org` ; `ios/Runner/Info.plist` ne déclare pas `UIBackgroundModes`. Le contrôle iOS signale l'absence de `aps-environment`. L'état signé de l'IPA et les capacités du compte Apple ne sont pas visibles ici, donc la réception APNs en production n'est **pas démontrée**. Apple décrit `aps-environment` comme l'entitlement des notifications distantes, et Firebase demande la capacité Push Notifications ainsi que les modes Background fetch/Remote notifications ([Apple](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment), [Firebase](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)). En outre `lib/services/notifications.dart:61-85` n'affiche une notification locale en premier plan que si `msg.notification.android != null` ; ce chemin exclut iOS. Aucun appel à `setForegroundNotificationPresentationOptions` n'apparaît, et Firebase indique que les notifications reçues au premier plan ne s'affichent pas par défaut ([Firebase](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)).

**Action :** activer la capacité Push Notifications dans Xcode/Apple Developer, contrôler l'entitlement dans l'IPA signé et la clé APNs du projet Firebase, puis définir explicitement la présentation au premier plan sur iOS. Tester sur build **production TestFlight** : app ouverte, arrière-plan et fermée, token FCM enregistré, réception et ouverture vers le bon écran. Transformer l'avertissement du préflight en échec si le push fait partie de la release.

### P1 — Résultats de recherche de talents incomplets et parfois faussement vides

`lib/services/users/talent_search_repository.dart:79-142` limite la requête à 30 documents sans curseur ni tri explicite. Quand poste **et** nationalité sont sélectionnés, la nationalité est filtrée **après** ces 30 lectures ; l'exclusion des comptes bloqués intervient aussi après la limite. `lib/screens/talent_search_screen.dart:64-90, 259-271` n'offre pas de chargement suivant. Un profil correspondant en 31e position reste invisible ; si les 30 premiers ne correspondent pas au filtre local, l'écran dit « aucun résultat » alors qu'il en existe. Le risque augmente avec la base.

**Action :** fournir une pagination stable avec `orderBy`/curseur, continuer les pages jusqu'à obtenir assez de résultats après les filtres locaux, ou déplacer toute la combinaison des filtres côté serveur. Tester plus de 30 profils avec les 30 premiers éliminés par nationalité ou blocage.

## Évolutivité et efficacité

| Priorité | Constat | Impact et action |
|---|---|---|
| P2 | `lib/services/users/user_repository.dart:183-198` plafonne l'annuaire à 300 sans pagination ; `lib/services/chat/chat_repository.dart:45,82-87` plafonne la boîte de réception à 200 sans ordre serveur. | Des personnes et conversations peuvent disparaître de la navigation quand les plafonds sont atteints. Ajouter tri serveur, index et pagination ; un simple relèvement des plafonds augmente les lectures. |
| P2 | `lib/services/home/home_feed_repository.dart:33-51` lit jusqu'à 300 joueurs pour la recherche du feed ; `home_screen.dart:522-560` filtre des auteurs en mémoire. | Recherche limitée et coût de lecture par session ; migrer la recherche d'auteur vers un index/query ou un service de recherche. |
| P2 | `functions/src/actions.ts:688-763` lit tous les joueurs pour chaque fanout puis envoie des lots de 500 **séquentiellement** dans l'appel utilisateur. | Coût O(nombre de joueurs), latence et risque de timeout/notification partielle sans reprise. Passer par une file/snapshot de campagne, progression et idempotence ; cibler uniquement les comptes éligibles. |
| P2 | `functions/src/follow_actions.ts:77-125` réécrit les listes entières de followers/followings dans deux documents à chaque action ; les likes, signalements et candidats utilisent aussi des tableaux sur un document. | Documents chauds, transactions conflictuelles et croissance vers la limite Firestore de 1 MiB ([Firebase](https://firebase.google.com/docs/firestore/quotas)). Prévoir sous-collections/relations et compteurs agrégés avant une forte croissance. |

## Stores, données et structure

| Priorité | Constat | Action avant release |
|---|---|---|
| P1 Android | `android/app/src/main/AndroidManifest.xml:9-10` demande `READ_MEDIA_IMAGES` et `READ_MEDIA_VIDEO` alors que les parcours inspectés utilisent `image_picker` ou `file_picker` pour une sélection ponctuelle. | Vérifier le manifeste **fusionné** de l'AAB final, retirer les permissions larges si non nécessaires, ou documenter le besoin réel et la déclaration Play. Google limite ces permissions aux usages nécessitant un accès large/fréquent ([Google Play](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en-GB)). |
| P1 conformité | `ios/Runner/PrivacyInfo.xcprivacy:9-10` a une liste `NSPrivacyCollectedDataTypes` vide, alors que l'application recueille identité, contenus, interactions et diagnostics ; `site_pub/legal/privacy-policy.html` est une page courte qui dit encore pouvoir être complétée. | Revoir les catégories du manifeste, les déclarations App Privacy et Data safety avec les traitements réels, y compris les SDK et toute publicité future ; publier les pages définitives. Apple demande de décrire la collecte dans le manifeste et App Store Connect ([manifeste](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)). |
| P1 contenu | Aucun SDK publicitaire ni flux de consentement à l'utilisation promotionnelle des images des joueurs n'a été identifié dans le code inspecté ; les notes Play actuelles indiquent « No ads » (`docs/play-store-submission-1.0.2+3.md:186,269`). | Avant d'utiliser visages/profils en publicité ou en captures, établir et conserver les autorisations appropriées, les droits des photographes et les modalités de retrait ; utiliser des comptes fictifs pour les captures lorsque possible. Actualiser les déclarations stores si des annonces ou traceurs sont ajoutés. Apple demande les droits sur les visuels et recommande des informations de compte fictives dans les captures ([règles App Review 2.3.9](https://developer.apple.com/app-store/review/guidelines/uk/)). Faire examiner le cas des mineurs avant tout usage. |
| P2 âge | L'écran de consentement demande une déclaration « 18 ans ou plus » (`lib/screens/terms_acceptance_screen.dart:45-49, 187-197`), mais `functions/src/user_search_fields.ts:70-92,117-133` accepte une année de naissance jusqu'à l'année courante et peut rendre ce profil recherchable. | Décider et documenter la règle d'âge effective ; si le service est réservé aux adultes, la faire appliquer au provisionnement et à la recherche, avec gestion des dates inconnues et des corrections admin. Ne pas utiliser d'image d'un joueur dont la situation est incertaine. |
| P2 dépendances | Audit Node : racine 11 avis, Functions 15 avis, dont `nodemailer` directement utilisé pour SMTP ; d'autres avis sont transitifs (`form-data`, `websocket-driver`, `uuid`, etc.). | Mettre d'abord à jour les corrections compatibles, retester lint/build/règles et le flux d'e-mail ; examiner séparément les mises à niveau majeures de Nodemailer/Firebase Admin. Ne pas déduire une exploitation effective du seul résultat `npm audit`. Ajouter l'audit de dépendances au gate CI avec triage documenté. |
| P2 maintenance | `.github/workflows/ci.yml` exécute analyze/tests Flutter, lint/build Functions et règles Firebase, mais aucun test d'intégration des callables ni build iOS/Android signé. Beaucoup de tests `guardrails` vérifient des chaînes source. | Ajouter quelques tests comportementaux ciblés : suppression partielle, push après blocage, fanout interrompu et pagination au-delà des plafonds. Conserver un smoke signé par plateforme avant promotion. |

## Ordre de décision avant publication

1. Vérifier **d'abord** la parité des règles, index, Functions et configuration de `adfoot-production` avec ce checkout ; les risques de règles ci-dessus restent conditionnés au déploiement. Ne faire aucune modification de production pendant l'audit.
2. Corriger les P1 de confidentialité, suppression et limitation des demandes de contact ; ajouter les tests de règles correspondants et les exécuter sur Java 21/CI.
3. Corriger le push direct, puis valider la réception iOS dans un IPA de production signé. S'il n'est pas prêt, retirer la promesse de notification des parcours concernés jusqu'à validation.
4. Régler la recherche tronquée et vérifier au moins un jeu de données dépassant 30 talents, 200 conversations et 300 profils.
5. Vérifier le manifeste Android final, les déclarations de données, la politique publiée et les droits sur les visuels. Le cas des annonces intégrées devra être réévalué si le produit ajoute réellement cette fonction.
6. Mettre à jour les dépendances, réaliser le smoke complet des parcours critiques sur Android internal test et iOS production TestFlight, puis relire Crashlytics, les échecs Functions et les événements de notifications/upload. Archiver les résultats et l'identifiant exact des artefacts validés.

## Limites de cet audit

Pas de Mac/Xcode ni de lecture de l'IPA signé depuis ce poste Windows ; pas de test de charge, test d'intrusion, accès aux consoles Firebase/Apple/Google, ni d'exécution locale des tests de règles. Le nombre et la gravité des avis Node dépendent de l'état du registre au 25 septembre 2026. La modification préexistante de `lib/widgets/ad_feedback.dart` a été laissée intacte.
