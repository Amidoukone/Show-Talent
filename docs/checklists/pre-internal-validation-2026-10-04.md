# Vérification avant tests internes — 4 octobre 2026

## État du candidat

Base Git : `fbd94bd`, branche `fix/audit-remediation-pre-release-2026-09`.
Version mobile : `1.0.7+42`. Vérification du contenu de travail, comprenant
les modifications préexistantes non commitées et les corrections de ce passage.
Portail examiné : `WEB/Show_talent_web` depuis `ODC_PROJECT`.
Aucun déploiement, modification de données distantes, publication store ou
changement de version effectué. La consultation de production était en lecture seule.

**Verdict : contrôles locaux réussis ; pas de feu vert pour tester ce nouveau
client contre la production actuelle, ni pour publier une release générale.**
Préparer et vérifier le backend du candidat sur un environnement de test avant
Internal testing / TestFlight.

## Défauts reproduits et corrigés

1. **Requêtes Firestore refusées malgré des tests unitaires verts.** Les
   contrôles d'âge sur les documents utilisateurs ne permettaient pas au moteur
   de règles de prouver l'autorisation d'une requête globale de vidéos ou de
   conversations. Ajout de `videos.publicFeedVisible` et
   `conversations.readableBy`, calculés par le serveur ; requêtes et trois
   index adaptés. La recherche de talents vérifiée filtre explicitement les
   marqueurs d'âge booléens, sans ouvrir les anciennes fiches non migrées.
2. **Échec d'enregistrement du consentement.** Les appels `set` de consentement
   contenaient des suppressions de champs sans option de fusion. Correction
   des deux parcours : provisionnement et modification du compte.
3. **Purge incomplète après panne.** Une première écriture effaçait `cvUrl` ;
   une nouvelle tentative pouvait donc oublier le fichier restant. La purge
   retrouve maintenant tous les CV dans l'espace du propriétaire et reprend
   un état `minorMediaPurgePending`, même après renouvellement du consentement.
4. **Reprovisionnement et retrait média.** Conservation de la photo lorsqu'elle
   est déjà autorisée ; purge lors d'une révocation média explicite ; retrait
   cohérent des références photo/CV quand une purge est requise.
5. **Édition d'un profil mineur.** Le formulaire renvoyait la date gérée par
   l'administration et les règles bloquaient aussi le téléphone. Le formulaire
   omet la date verrouillée ; le téléphone reste modifiable sans autoriser
   de changement de date.
6. **Calcul d'âge et déclencheurs.** Les champs de recherche sont désormais
   dérivés en transaction ; le déclencheur contact relit l'état courant.
   Une date invalide ne retire plus un marqueur de protection ni ne produit
   une année `NaN`.
7. **Page publique de partage vidéo.** `/v/...` utilise Admin SDK et contournait
   les règles. Elle exige maintenant l'audience publique et un propriétaire
   actuellement adulte. Les médias mineurs ne sont pas exposés par cette page.

Les transitions administratives vers un profil protégé mettent à jour les
audiences des vidéos et conversations dans la transaction du compte, avant
les suppressions Storage. Une panne Storage laisse un état de reprise visible,
sans réouvrir les listes.

## Vérifications exécutées

| Contrôle | Résultat |
| --- | --- |
| `flutter test --reporter expanded` mobile | 959 réussis |
| `flutter analyze` mobile | Aucune anomalie |
| Functions : compilation TypeScript, ESLint, tests | Réussite ; 12 tests |
| Firestore sur émulateur, avec scénarios backend | 96/96 |
| Storage sur émulateurs Firestore + Storage | 30/30 |
| Portail : `npm run release:check` | 30 tests, analyse et contrôles réussis |
| Contrat partagé admin/mobile | Réussite |
| Android : readiness production avec Play Integrity | Réussite |
| iOS : readiness production | Réussite ; `Podfile.lock` absent, résolution macOS à faire |
| `git diff --check` | Réussite |
| Parité avec production | Échec attendu : règles différentes et 12 index manquants |

Les nouveaux tests comprennent les requêtes de liste, la création de
conversation, le refus des droits falsifiés, la correction adulte → mineur,
l'enregistrement du consentement, le reprovisionnement et une panne Storage
suivie d'une reprise. Les écritures Firestore de ces scénarios sont réelles
sur émulateur ; Auth, SMTP et Storage des tests de callable sont simulés.
Les tests Storage séparés utilisent le moteur de règles Storage.

Les émulateurs ont utilisé le Java 25 fourni par Android Studio, sélectionné
uniquement pour les processus de test. Le Java 17 employé par le contrôle
Android ne permet pas de démarrer cette version des émulateurs.

Journaux locaux :

- `artifacts/audit-2026-10-04-flutter-test.log`
- `artifacts/audit-2026-10-04-rules.log`
- `artifacts/audit-2026-10-04-admin.log`
- `artifacts/audit-2026-10-04-backend-parity.log`

## Préparation obligatoire avant la recette sur appareils

1. Figer les révisions mobile, Functions et portail qui formeront le candidat.
2. Sur un environnement de test isolé, préparer les Functions, notamment
   `syncVideoAudience`, les règles et les index correspondants. Attendre les
   index `READY` puis vérifier la parité de cet environnement.
3. Exécuter la préparation des profils/audiences via le backfill v4 mis à jour.
   Vérifier `isMinorProfile`, `publicFeedVisible`, `readableBy` et les dates de
   tri sur des données historiques. Un ancien indicateur v4 `completed=true`
   ne prouve pas l'exécution de cette nouvelle logique : prévoir une nouvelle
   passe contrôlée si nécessaire.
4. Les anciens clients et les anciennes règles transitoires ne sont pas
   compatibles avec toutes les nouvelles requêtes. Tester la stratégie de
   migration avant toute bascule de production ; ne pas déployer les règles
   finales isolément. Voir le runbook `public-profile-rollout-2026-09-28.md`.
5. Construire l'AAB signé et l'IPA sur macOS/Codemagic contre le backend retenu,
   relever version et empreintes, puis distribuer aux testeurs internes.

## Recette Android / TestFlight

- Invitation admin → définition du mot de passe → connexion et reconnexion.
- Profil adulte et mineur ; recherche FR/EN avec filtres et pagination ; accès
  différent selon recruteur vérifié, recruteur non vérifié et joueur.
- Profil mineur sans consentement, accord profil, accord média, retrait et
  nouvelle tentative après erreur. Vérifier le portail et le mobile ensemble.
- Flux vidéo, page auteur, upload/modération, reprise après interruption,
  partage public adulte et refus du partage public mineur.
- Conversations adultes, première prise de contact, historiques migrés,
  blocage, signalement ; demande mineure transmise à l'administration.
- Offres/événements : création admin, consultation et candidature/participation
  selon les droits. CV : ajout, remplacement, ouverture native iOS/Android.
- Notifications, suppression de compte, liens profonds, retour d'arrière-plan,
  permissions refusées et réseau lent/coupé.

Relever pour chaque anomalie : compte/rôle de démonstration, version du binaire,
heure, parcours, environnement, résultat attendu et erreur journalisée.

## Limites et points de release encore ouverts

- Aucun AAB/IPA nouveau n'a été construit ou installé pendant ce passage.
  La validation iOS effectuée ici est statique sous Windows.
- La parité des Functions effectivement déployées, les migrations terminées,
  les performances et les parcours sur appareils restent à constater.
- Le site public a été examiné via ses sources/configuration et les contrôles
  automatisés existants ; pas de recette navigateur complète du site déployé.
- Les CGU et la nouvelle politique sont encore des brouillons exclus de
  Hosting. `site_pub/legal/terms.html` est absent et la version CGU embarquée
  reste vide : finaliser/publiciser les documents avant d'activer l'acceptation.
- Bloquer `/v/...` ne révoque pas les jetons de téléchargement Firebase déjà
  partagés ni les copies externes. La restriction des liens média mineurs doit
  être validée avant d'annoncer une confidentialité absolue.
- La synchronisation atomique des audiences lit les contenus/conversations du
  compte ; sa capacité pour des comptes de très gros volume n'a pas été mesurée.
