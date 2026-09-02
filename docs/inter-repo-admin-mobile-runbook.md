# PRD / Runbook d Exploitation Inter-Depots
Date de reference : 17 avril 2026

## Objet

Ce document definit le contrat commun entre :

- l application mobile publique Adfoot
- le portail admin Flutter
- le backend Firebase partage

## Backend partage

Les deux depots utilisent obligatoirement le meme backend Firebase selon
l environnement actif :

- `APP_ENV=local` -> `adfoot-staging`
- `APP_ENV=staging` -> `adfoot-staging`
- `APP_ENV=production` -> `adfoot-production`
- region Functions pour les callables admin : `europe-west1`

Le portail admin n est pas un backend separe. C est une surface
d administration du meme socle Firebase que l application mobile publique.

## Politique de roles

Aucune creation publique mobile n est autorisee.

Tous les comptes metier sont crees par l administration :

- `joueur`
- `fan`
- `club`
- `recruteur`
- `agent`

Role Firestore d un operateur admin :

- `admin`

Claims admin reconnus :

- `admin`
- `platformAdmin`
- `superAdmin`

Le niveau reel d administration repose sur les custom claims, pas sur le seul
champ Firestore `role`.

## Contrat produit commun

L application mobile publique doit :

- refuser toute creation publique de compte metier
- refuser la connexion si `/users/{uid}` est absent
- refuser la connexion si `authDisabled == true`
- refuser les comptes reserves au portail admin

Le portail admin doit :

- authentifier uniquement des operateurs admin valides
- exiger un document `/users/{uid}`
- refuser l acces si `role != 'admin'`
- refuser l acces si `authDisabled == true`
- refuser l acces si aucun claim `admin|platformAdmin|superAdmin` n est present
- ne jamais creer d admins cote client
- ne jamais creer de comptes metier via Auth ou Firestore cote client

## Cloud Functions admin partagees

Le portail admin consomme exclusivement les callables suivantes.

Gestion de comptes :

- `provisionManagedAccount`
- `deleteManagedAccount`
- `changeManagedAccountRole`
- `resendManagedAccountInvite`
- `disableManagedAccountAuth`
- `enableManagedAccountAuth`
- `updateManagedAccountProfile`
- `setManagedAccountMembership`

Moderation de contenu :

- `adminSetOfferStatus`
- `adminDeleteOffer`
- `adminSetEventStatus`
- `adminDeleteEvent`
- `adminSetVideoStatus`
- `adminRejectVideo`
- `adminDeleteVideo`
- `adminSetContactIntakeFollowUp`
- `adminDeleteContactIntake`
- `adminDeleteContactIntakeConversation`

Ces 18 callables sont verifiees automatiquement par
`scripts/check-admin-mobile-contract.ps1` (`npm run contract:mobile` /
`npm run contract:admin-mobile:check`). `submitContactIntakeFeedback` est un
callable participant, pas un callable admin, et reste hors de cette liste.

Toutes les fonctions admin doivent etre appelees via :

- `FirebaseFunctions.instanceFor(region: AppEnvironmentConfig.functionsRegion)`

## Contrat operateur admin

Un operateur admin valide doit exister :

- dans Firebase Auth
- dans Firestore sous `/users/{uid}`

Le document Firestore attendu doit rester coherent avec le backend partage :

- `role: 'admin'`
- `authDisabled: false`
- `createdByAdmin: false`

## Bootstrap admin

La creation d un operateur admin se fait uniquement cote Admin SDK depuis le
depot admin.

Script de reference :

- `scripts/create_admin_account.mjs`

Ce script doit :

- creer ou mettre a jour le compte Firebase Auth
- poser ou normaliser le custom claim `admin`, `platformAdmin` ou `superAdmin`
- creer ou mettre a jour `/users/{uid}`
- exiger un `projectId` explicite via `--projectId` ou `FIREBASE_PROJECT_ID`

## Provisionnement des comptes

Les comptes `joueur`, `fan`, `club`, `recruteur` et `agent` sont crees
uniquement via `provisionManagedAccount`.

Regles operateur :

1. Se connecter au portail admin avec un operateur valide.
2. Ouvrir la surface de provisionnement.
3. Saisir nom, e mail, telephone eventuel et role cible.
4. Appeler `provisionManagedAccount`.
5. Recuperer `uid`, `email`, `role`, `existingUser`,
   `passwordSetupLink`, `emailVerificationLink`.
6. Transmettre les liens au titulaire via un canal maitrise.
7. Verifier que `/users/{uid}` existe et porte le bon role.
8. Verifier que le compte cree ne possede aucun claim admin.

## Cycle de vie des comptes provisionnes

Les actions cross-user doivent passer uniquement par les callables backend
partagees :

- desactivation Auth via `disableManagedAccountAuth`
- reactivation Auth via `enableManagedAccountAuth`
- changement de role via `changeManagedAccountRole`
- renvoi des liens via `resendManagedAccountInvite`
- suppression via `deleteManagedAccount`
- mise a jour profil via `updateManagedAccountProfile`

Un compte est traite comme compte administre si :

- `createdByAdmin == true`
- ou `role` appartient a `club|recruteur|agent`

## Checklist de validation croisee

La plateforme est consideree coherente si :

- les deux depots ciblent le meme `APP_ENV`, `FIREBASE_PROJECT_ID` et
  `FIREBASE_FUNCTIONS_REGION`
- les callables admin passent bien via `europe-west1`
- l application mobile n ouvre aucun self-signup public
- le portail admin ne cree plus aucun compte sensible cote client
- tous les comptes metier sont provisionnes uniquement via backend partage
- toute nouvelle requete `where()`/`orderBy()` ajoutee a une requete
  `collectionGroup('private')` (admin, `lib/controller/user_controller.dart`)
  a son entree `COLLECTION_GROUP` correspondante dans `firestore.indexes.json`
  avant deploiement — la regle `list` (`firestore.rules`) fonctionne
  aujourd'hui sans filtre, un index manquant casse en production des le
  premier filtre ajoute
- `scripts/audit_admin_claims.mjs` a ete execute sans ecart avant tout
  deploiement qui touche `assertAdminCaller()` / `isAdminOperator()`

## Controle serveur admin (claims uniquement)

`assertAdminCaller()` (`functions/src/admin_account_support.ts`) et
`isAdminOperator()` (`firestore.rules`) n'acceptent que le custom claim
`admin`/`platformAdmin`/`superAdmin` — le champ Firestore `role` seul n'ouvre
plus aucun acces admin, cote serveur comme cote regles. `role: 'admin'` reste
utile pour l'UI et les regles client, mais n'est plus une porte d'entree a
lui seul. `scripts/create_admin_account.mjs` continue de poser les deux
ensemble, donc ce resserrement ne change rien au provisionnement normal —
seulement a un contournement (edition manuelle Firestore) qui ne doit plus
suffire.

## Ordre de deploiement entre les deux depots

### La regle : le lecteur avant l ecrivain

Un champ partage a toujours un depot qui l ecrit et un depot qui le lit. Le
lecteur doit etre deploye **avant** l ecrivain, jamais l inverse.

L ordre est donc, sans exception :

1. **Regles Firestore et Cloud Functions** (depuis le depot mobile, seul a les
   deployer)
2. **Build mobile** publie et installe
3. **Portail admin**

### Pourquoi cet ordre, et pas un autre

L exemple qui a impose la regle, en septembre 2026 : le portail ecrivait
`team`, le formulaire avance du mobile ecrivait `currentClubName`, et la fiche
affichait tantot l un tantot l autre. La correction fait ecrire
`currentClubName` au portail.

- Portail deploye **apres** le mobile : le portail de production ecrit encore
  `team`, et le nouveau mobile lit `currentClubName ?? team ?? clubActuel`.
  La correction arrive sur le telephone par le champ de secours. Rien ne casse.
- Portail deploye **avant** le mobile : le portail ecrit `currentClubName`, que
  l ancien mobile ne lit pas. Une correction de club faite par un
  administrateur devient invisible sur tous les telephones, **sans aucune
  erreur nulle part**. C est une panne silencieuse, la pire a diagnostiquer.

Meme raisonnement pour les regles : elles doivent preceder le build qui en a
besoin. Un client qui ecrit un champ absent de `canUpdateOwnProfile` est
refuse par `changesOnly()`, et comme cette fonction refuse **tout** l
enregistrement, l utilisateur perd aussi les modifications qui, elles, etaient
permises.

### Partie 1 — ce que le depot mobile doit porter

Le depot mobile est la source d autorite. Il porte :

- `firestore.rules` et `firestore.indexes.json` — c est le seul depot qui les
  deploie
- les Cloud Functions, dont la liste blanche du callable
  `updateManagedAccountProfile` (`sanitizeManagedProfilePatch` et
  `applyFootballFields`, `functions/src/admin_account_actions.ts`)
- les modeles de reference, ceux que le depot admin recopie :
  `lib/models/player_football_profile.dart`, `lib/models/football_vocabulary.dart`,
  `lib/models/org_football_profile.dart`, `lib/utils/country_codes.dart`
- `_trustSensitiveProfileKeys` (`lib/services/users/profile_repository.dart`),
  qui doit rester le miroir exact de `ownerProfileTrustFieldsChanged()` dans
  les regles
- la lecture de secours des anciens champs (`currentClubName ?? team ??
  clubActuel`) tant que des comptes anterieurs a une bascule existent

### Partie 2 — ce que le depot admin doit porter

Le depot admin est un consommateur. Il porte :

- la **copie exacte** des modeles de reference. Elle se regenere depuis le
  fichier mobile, en ne conservant que deux differences : l en-tete qui
  explique la duplication, et le nom du paquet (`show_talent` au lieu de
  `adfoot`). Une divergence silencieuse produit un code que le mobile lit
  comme nul, donc une fiche qui perd un champ sans erreur.
- des ecritures **uniquement via les callables**. Le portail n ecrit jamais
  directement dans `users/` : le SDK Admin contourne firestore.rules, et la
  validation cote callable est alors la seule qui existe.
- les champs types, jamais les anciens : `positionCodes` et non `position`,
  `currentClubName` et non `team` ni `clubActuel`
- un `toEmbeddedMap()` de meme forme que celui du mobile — ni `email` ni
  `phone`, qui vivent dans `users/{uid}/private/contact`. Les regles comparent
  ces lignes par valeur (`hasAll(currentOfferCandidates())`).
- aucune ecriture des champs derives par le serveur (`birthYear`,
  `isSearchable`) : ils seraient ecrases a la passe suivante du trigger, ce qui
  se lit comme un bug plutot que comme la regle.

### Ajouter un fait footballistique : les cinq endroits

Un champ oublie a l un de ces endroits echoue en silence ou casse tout l
enregistrement. Dans l ordre :

| # | Endroit | Depot |
| --- | --- | --- |
| 1 | Le modele + `writableFieldPaths` | mobile |
| 2 | `canUpdateOwnProfile()` **et** `ownerProfileTrustFieldsChanged()` | mobile (`firestore.rules`) |
| 3 | `_trustSensitiveProfileKeys` | mobile (`profile_repository.dart`) |
| 4 | Le validateur du callable | mobile (`functions/src/`) |
| 5 | Le miroir du modele, regenere | admin |

Trois garde-fous attrapent les oublis, et il faut les laisser faire :

- `test/player_football_profile_test.dart` confronte `writableFieldPaths` a la
  liste blanche des regles
- `test/profile_trust_parity_guardrails_test.dart` confronte la liste du client
  a celle des regles
- `test/football_vocabulary_parity_test.dart` confronte le vocabulaire Dart au
  vocabulaire TypeScript

### Avant et apres chaque deploiement

- `npm run contract:mobile` (depot admin) — verifie les fichiers partages et
  les miroirs
- `scripts/check-backend-parity.ps1` (depot mobile) — verifie que les regles,
  les index et les TTL deployes correspondent au checkout. **Il ne couvre pas
  les Cloud Functions** : leur presence se verifie avec
  `firebase functions:list`.
- deployer les Functions avec `scripts/deploy-functions-safe.ps1`
  (`-DiscoveryTimeoutSeconds 120`) : il valide les fichiers d environnement
  d abord, et un `firebase deploy --only functions` nu expire a l analyse du
  code sur les machines lentes.

Attention : un backend deploye depuis une branche non fusionnee fait signaler
au controle de parite une derive qui est un artefact de la branche. Fusionner
remet les deux en phase.

## Conclusion

Le modele cible commun est desormais :

- operateurs admin dans Auth + `/users`
- claims admin obligatoires pour les operateurs
- comptes `joueur|fan|club|recruteur|agent` crees uniquement par backend partage
- mobile public sans creation de compte
- portail admin comme seule surface legitime d administration
- backend Firebase partage comme source d autorite unique
