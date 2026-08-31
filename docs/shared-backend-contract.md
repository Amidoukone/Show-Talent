# Admin / Mobile Shared Backend Contract

Le projet mobile public et le projet admin utilisent le meme backend Firebase
partage, mais cible selon l environnement actif :

- `APP_ENV=local` -> projet Firebase `adfoot-staging`
- `APP_ENV=staging` -> projet Firebase `adfoot-staging`
- `APP_ENV=production` -> projet Firebase `adfoot-production`
- region Functions admin : `europe-west1`

Le `projectId` effectif est determine par `APP_ENV` et `FIREBASE_PROJECT_ID`.
Le `Storage bucket` suit le projet Firebase actif.

## Roles

Aucune creation publique mobile n est autorisee.

Tous les comptes metier sont provisionnes par l administration :

- `joueur`
- `fan`
- `club`
- `recruteur`
- `agent`

Role Firestore des operateurs admin :

- `admin`

Claims admin reconnus :

- `admin`
- `platformAdmin`
- `superAdmin`

Le niveau reel d administration repose sur les custom claims, pas sur le seul
champ Firestore `role`.

## Mobile public

L application mobile publique :

- n ouvre plus aucun parcours de creation publique
- refuse la connexion si `/users/{uid}` est absent
- refuse la connexion si `authDisabled == true`
- refuse les comptes reserves au portail admin

## Portail admin

Le portail admin :

- authentifie uniquement des operateurs admin valides
- exige un document `/users/{uid}`
- exige `role == 'admin'`
- exige au moins un claim `admin|platformAdmin|superAdmin`
- refuse `authDisabled == true`
- ne cree plus d admins cote client
- provisionne tous les comptes metier via backend partage

## Cloud Functions admin

Toutes les operations sensibles passent par les callables backend partagees :

Gestion de comptes :

- `provisionManagedAccount`
- `deleteManagedAccount`
- `changeManagedAccountRole`
- `resendManagedAccountInvite`
- `disableManagedAccountAuth`
- `enableManagedAccountAuth`
- `updateManagedAccountProfile`
- `setManagedAccountMembership`

Moderation de contenu (appelees depuis `AdminContentService` cote admin) :

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

### Droits d acces : `setManagedAccountMembership`

Enregistre ou retire les droits d acces d un compte : `tier` valant `adfoot`
(joueur sous contrat avec l agence, ne paie rien), `external` (joueur libre qui
paie les services), ou `none` (aucun dossier, etat par defaut de tout compte
existant). Champs optionnels : `validUntil` (date ISO ou millisecondes, cinq
ans maximum) et `reference` (reference interne du paiement ou du contrat).

Ce callable ne connait aucun prix et ne deplace aucun argent. Le paiement a
lieu hors plateforme et l administration enregistre le resultat ; l application
mobile n affiche aucun prix, n offre aucun moyen de payer et ne renvoie vers
aucun. C est ce qui maintient vraie la declaration Play Console « aucun achat
integre ». Ne pas ajouter de montant a la charge utile.

Le portail admin l appelle depuis « Gestion des utilisateurs » (action
« Gerer les droits »), via `ManagedAccountService.setManagedAccountMembership`.
Il est donc dans `$requiredCallables` de
`scripts/check-admin-mobile-contract.ps1`, avec son entree dans
`lib/utils/admin_callable_action_catalog.dart` cote admin.

### Liste verifiee par le garde-fou

Ces 18 callables sont la liste complete et doivent rester en phase avec
`functions/src/index.ts`, `lib/utils/admin_callable_action_catalog.dart` (admin)
et `lib/services/admin_content_service.dart` (admin) -- verifie par
`scripts/check-admin-mobile-contract.ps1`. `submitContactIntakeFeedback` est
volontairement absent : c'est un callable participant, pas un callable admin.

Le portail admin doit appeler ces fonctions via :

- `FirebaseFunctions.instanceFor(region: AppEnvironmentConfig.functionsRegion)`

## Bootstrap admin

Les operateurs admin sont crees uniquement via Admin SDK, depuis le depot
admin, avec :

- `scripts/create_admin_account.mjs`

Le bootstrap doit :

- creer ou mettre a jour Firebase Auth
- poser le custom claim admin
- creer ou mettre a jour `/users/{uid}`

Le document Firestore admin attendu :

- `role: 'admin'`
- `authDisabled: false`
- `createdByAdmin: false`

## Comptes provisionnes

Les comptes `joueur`, `fan`, `club`, `recruteur` et `agent` sont provisionnes
uniquement via `provisionManagedAccount`.

Le portail admin recupere :

- `uid`
- `email`
- `role`
- `existingUser`
- `passwordSetupLink`
- `emailVerificationLink`
- `inviteEmailSent` : le backend a expedie l invitation lui meme
- `inviteEmailReason` : `not_configured` | `send_failed` | `invalid_recipient`,
  ou `null` quand l envoi a reussi

`passwordSetupLink` est retourne dans tous les cas, envoi reussi ou non. C est
le repli de l admin, et c est ce qui fait qu une panne du relais SMTP coute un
copier coller et jamais un compte injoignable. Un portail plus ancien, qui ne
lit pas les deux nouveaux champs, continue de fonctionner a l identique.

Le cycle de vie d un compte provisionne repose uniquement sur :

- la verification d e mail
- `authDisabled`
- la suppression definitive

## Regle de coherence

Le backend Firebase partage est la source d autorite unique pour :

- Auth
- custom claims
- Firestore `/users`
- cycle de vie des comptes crees par l administration
