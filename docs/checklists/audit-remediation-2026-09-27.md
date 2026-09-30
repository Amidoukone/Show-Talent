# Suite de l'audit global — 27 septembre 2026

Ce document suit les corrections du rapport `audit-global-2026-09-25.md` dans le dépôt local. Aucun déploiement Firebase, IPA ou AAB signé n'a été effectué pendant cette intervention.

## Corrections intégrées

- **Confidentialité** : les documents complets `users/{uid}` sont réservés au propriétaire et aux opérateurs autorisés. Les autres comptes lisent une projection `public_profiles` limitée ; un profil privé ne publie que son identité nécessaire à la messagerie. Le jeton FCM est stocké hors du profil public. Les nouveaux CV utilisent un chemin Storage contrôlé par les règles ; une migration retire les anciennes URL de téléchargement des profils.
- **Suppression de compte** : suppression directe du profil refusée par les règles ; nettoyage serveur des sous-collections et relations ; reprise planifiée si la suppression Firebase Auth échoue. Le client reconnaît l'état incomplet.
- **Abus et notifications** : quota des demandes de contact vérifié dans l'écriture atomique ; notification de message liée à un message récent, au destinataire et à l'absence de blocage, avec reçu anti répétition. Les fanouts d'offres et d'événements sont placés en file et traités par pages avec reprise et suivi des résultats.
- **Recherche et volume** : pagination des talents et des conversations, annuaire paginé, recherche indexée des auteurs avec balayage des pages jusqu'au nombre de correspondances demandé, suivis stockés en relations plutôt qu'en tableaux. Les conversations vides conservent leur champ de tri ; une migration répare les documents historiques qui ne l'ont pas.
- **Mobiles et conformité locale** : chemin explicite de notification iOS au premier plan, entitlement push iOS dans le projet, permissions Android réduites, manifeste de confidentialité et politique de confidentialité revus. Les dépendances Node avec avis de gravité élevée ont été mises à jour ou corrigées dans les verrous.
- **Visualisation du CV** : l'application ne demande plus d'URL de téléchargement Firebase. Une Function vérifie le compte, le caractère public du profil ou le droit propriétaire/admin, puis délivre un lien PDF sous le domaine configuré (`https://adfoot.org/cv/view/...` en production), valable cinq minutes. Le PDF est servi directement par une seconde Function avec `Content-Disposition: inline`, prise en charge des requêtes Range de Safari et en-têtes interdisant le cache. Le lien est invalidé si le CV est retiré, remplacé, rendu privé ou si le compte perd son droit d'accès. Le chemin CV est exclu des liens universels iOS pour rester dans Safari.

## Vérifications locales

- `flutter analyze` sans erreur, 953 tests Flutter réussis lors de la revue complète, lint et compilation TypeScript des Functions. Un test comportemental supplémentaire vérifie ensuite le passage au-delà d'une page de résultats filtrés.
- Règles Firestore : 67/67 ; règles Storage : 25/25, avec l'émulateur Firebase et le JBR d'Android Studio.
- Contrôles de préparation iOS et Android, scan des secrets suivis, `git diff --check`.
- `npm audit --omit=dev --audit-level=high` ne remonte plus d'avis high/critical dans la racine ni dans `functions` ; les avis modérés restent à suivre.

## À vérifier avant la publication

1. **Ordre de mise en service** : déployer les index, les Functions et les règles de manière coordonnée ; exécuter et surveiller le remplissage de `public_profiles`, des relations de suivi et des dates de tri avant de distribuer un client qui s'appuie dessus. Vérifier la parité réelle du backend et des règles déployées. La protection des données n'est effective qu'après ce déploiement.
2. **Parcours réels** : sur staging, tester profil privé, suppression partielle/reprise Auth, contact et blocage, recherche au-delà des premières pages, conversation vide, fanout interrompu puis repris. Surveiller les compteurs et erreurs des campagnes. La livraison FCM reste de type « au moins une fois » autour d'une interruption entre l'envoi et l'enregistrement du curseur ; des doublons sont possibles dans ce cas.
3. **iOS signé** : contrôler `aps-environment` et la capacité Push Notifications dans l'IPA final, les clés APNs/Firebase, puis tester les notifications en arrière-plan et au premier plan sur TestFlight. Le contrôle Windows du projet ne prouve pas le contenu de l'IPA signé.
   Pour le CV, déployer `createCvViewLink`, `cvViewPage` et la réécriture Hosting `/cv/view/**` avant de diffuser l'application. Sur TestFlight, ouvrir un CV public et son propre CV : l'adresse affichée doit rester sous `adfoot.org`, le PDF doit s'afficher et les demandes Range doivent réussir. Vérifier qu'un compte non autorisé ne reçoit pas de lien, qu'un lien expiré ou un CV devenu privé ne s'ouvre plus, et que `/cv/view/*` reste dans Safari malgré les liens universels des vidéos.
4. **Stores et contenu** : confirmer les déclarations App Privacy/Data safety, les droits d'image des joueurs et photographes, et utiliser des comptes fictifs dans les captures lorsque possible. Vérifier les versions finales des pages légales.

La modification locale préexistante de `lib/widgets/ad_feedback.dart` a été laissée intacte. Les déploiements sont réservés à une étape ultérieure.
