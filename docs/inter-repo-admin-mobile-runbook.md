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

Ces 17 callables sont verifiees automatiquement par
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

## Conclusion

Le modele cible commun est desormais :

- operateurs admin dans Auth + `/users`
- claims admin obligatoires pour les operateurs
- comptes `joueur|fan|club|recruteur|agent` crees uniquement par backend partage
- mobile public sans creation de compte
- portail admin comme seule surface legitime d administration
- backend Firebase partage comme source d autorite unique
