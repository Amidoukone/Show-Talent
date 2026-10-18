# Play Store Submission : Adfoot 1.0.8+54

Reference date: 18 October 2026

Premiere mise a jour apres la mise en production du `1.0.7+52`. Ce document
enregistre ce qui a ete verifie pour *ce* build, a quelle date, par quelle
commande. Il ne remplace pas la liste generique de
`docs/checklists/android-release-checklist.md`.

## Etat constate le 18 octobre 2026 : le 52 est bien en production

La soumission 3 de la Play Console porte `Status: Published`, `Changes
submitted Oct 16, 2026, 10:35 am`, publiee le `Oct 18, 2026, 1:55 pm`, et ses
huit changements incluent `Start full rollout`, `Add 177 countries/regions` et
`Add rest of world`. Le deploiement est donc complet, pas progressif.

Verifie independamment de la console, depuis l'exterieur :

| Controle | Resultat |
| --- | --- |
| `play.google.com/store/apps/details?id=org.adfoot.app` | HTTP 200, fiche complete |
| Meme requete avec un identifiant inexistant | HTTP 404, ce qui rend le 200 ci-dessus concluant |
| Bouton de la fiche | « Installer », et non « Rejoindre le test » |
| Version servie | `1.0.7`, `minSdk 24` (Android 7.0), `targetSdk 36` |
| Date affichee | 16 oct. 2026 |
| Marqueurs test ouvert / acces anticipe / beta | aucun |
| Fiche resolue pour CI, SN, ML, BF, CM, MA, FR, BE, CA, US | HTTP 200 partout |

Le courriel IARC du 18 octobre (`Global Rating ID
8cdcb5f1-6802-8f6f-80e0-3fad2992ee38`) n'est pas une notification de
publication. Il dit que les classifications issues du questionnaire soumis ce
jour-la sont actives. Aucune action n'en decoule, et il ne prouve rien sur
l'etat de la publication.

## Pourquoi 54 et non 53

Le `53` a ete consomme par la soumission iOS du 17 octobre (`f1d2f67`), en
revue chez Apple. Un numero televerse ne se reutilise pas, et faire porter a
deux plateformes le meme numero pour du contenu different laisserait deux
dossiers contradictoires sous un seul numero. Le nom de version passe a
`1.0.8` pour la meme raison : le `1.0.7` en ligne porte un code Dart
different de celui-ci.

## iOS n'est pas touche, deliberement

Le binaire iOS en revue a ete construit a `f1d2f67`, qui est **anterieur** aux
trois corrections ci-dessous : il ne les contient pas. Modifier
`pubspec.yaml` n'a aucun effet sur un binaire deja televerse, donc la revue
Apple n'est pas menacee par ce build. Elle le serait par un nouveau
televersement iOS. **Ne rien reconstruire ni renvoyer cote iOS avant la fin
de la revue.** Le prochain build iOS partira de `1.0.8+55`.

## Ce que ce build contient que le 52 n'a pas

| Commit | Ce qui change pour un utilisateur |
| --- | --- |
| `522c4cd` | Le vocabulaire footballistique est traduit. En anglais, les postes, pieds forts et statuts de contrat restaient affiches en francais. |
| `99f3b25` | Rien pour l'utilisateur : audit de la lecture video, consigne dans `docs/audit-lecture-video-2026-10-17.md`. |
| `0722700` | Une video reprend la ou le spectateur l'avait laissee en quittant l'onglet, au lieu de repartir de 0:00. |
| ce build | Les six messages de refus d'un CV suivent la langue de l'application. |

### Le bug CV, et pourquoi il avait survecu a `522c4cd`

`CvUploadValidationException` portait la phrase francaise elle-meme, et
`ProfileController.uploadCvPdf` affichait `e.message` tel quel sous un titre,
lui, traduit (`'profileCvRejectedTitle'.tr`). Un utilisateur en anglais lisait
donc « CV not accepted » suivi de « Le CV doit faire 5 Mo maximum. ».

L'exception porte maintenant une cle de traduction GetX, resolue par `.tr` a
l'endroit ou le message est montre. Le repository n'a aucun `BuildContext` et
ne doit pas choisir de langue, ce qui est exactement la raison pour laquelle
le mecanisme GetX existe a cote de l'ARB dans ce depot.

Six cles ajoutees dans `lib/l10n/video_ui_translations.dart`, cote `_fr` et
cote `_en` : `profileCvErrorProfileInvalid`, `profileCvErrorLinkInvalid`,
`profileCvErrorFileUnreadable`, `profileCvErrorFileEmpty`,
`profileCvErrorTooLarge`, `profileCvErrorNotPdf`. Onze sites de `throw`
bascules dans `lib/services/users/profile_repository.dart`.

### Ce que les temoins de contenu ne peuvent pas prouver ici

Les trois commits posterieurs au 52 n'ajoutent **aucune chaine de caracteres
nouvelle** au bundle : leurs diffs ne contiennent que des imports et des
commentaires, et un commentaire ne survit pas a la compilation. Aucun temoin
de `scripts/aab-content-expectations.json` ne peut donc les attester, et ce
sont les tests de regression qui s'en chargent. Le correctif CV, lui, ajoute
des chaines, d'ou les trois temoins ajoutes pour le 54 :

- `mustContain` « The CV must be 5 MB or smaller. », la valeur anglaise neuve
- `mustContain` « profileCvErrorTooLarge », la cle, presente des deux cotes
  du nouveau contrat
- `mustNotContain` « Le CV doit etre un PDF valide. », graphie **sans accent**
  que portaient les sites de `throw` jusqu'au 52 inclus. Le libelle traduit
  qui le remplace ecrit « etre » avec son accent, donc cette graphie
  n'existe plus dans le bundle. C'est le seul des six messages dont
  l'ancienne et la nouvelle forme se distinguent par les octets, les cinq
  autres etant identiques en francais.

## Copie du Store a coller

Deux fiches existent : `French (France) - fr-FR` et la fiche par defaut, en
anglais.

### Defaut constate sur la fiche en ligne

Le champ « Nouveautes » du 52 est **en francais sur les deux fiches**. Un
utilisateur anglophone lit donc du francais dans la section Nouveautes. Le
texte anglais ci-dessous corrige cela.

Par ailleurs « Premiere version publique d'Adfoot » devient faux sur une mise
a jour. Le champ decrit desormais ce qui change.

### Nouveautes, fiche fr-FR

A coller tel quel : un paragraphe par ligne, aucune coupure en
milieu de phrase.


```
Adfoot, le réseau du football africain.

Version anglaise complétée. Les postes, le pied fort et le statut de contrat s'affichent maintenant en anglais pour les utilisateurs qui ont choisi cette langue.

Lecture vidéo. Une vidéo reprend là où vous l'aviez laissée lorsque vous revenez sur l'accueil, au lieu de repartir du début.

Ajout d'un CV. Un refus est désormais expliqué dans la langue de l'application.
```

### Nouveautes, fiche par defaut (anglais)

```
Adfoot, the network for African football.

Completed English translation. Positions, strong foot and contract status now appear in English for users who chose that language.

Video playback. A video resumes where you left off when you return to the home feed, instead of starting over.

CV upload. A rejected file is now explained in the language of the app.
```

### Description complete, fiche fr-FR

Seule la premiere phrase change. Le reste est repris mot pour mot de la
version en ligne, qui est exacte sur les comptes, l'age minimum et l'accord
parental, et qu'il ne faut pas reecrire.

Avant : `Adfoot est un réseau professionnel du football au Mali.`
Apres : `Adfoot est un réseau professionnel du football africain.`

Texte complet a coller (copie de confort dans
`artifacts/store-copy-1.0.8+54/description-fr.txt`, non suivi par git) :

```
Adfoot est un réseau professionnel du football africain. Il réunit les joueurs, les clubs, les recruteurs et les agents dans un cadre vérifié.

Les comptes sont créés par l'administration Adfoot après vérification de l'identité. L'application ne propose pas d'inscription libre : la demande de compte se fait sur adfoot.org. Pour un joueur de 13 à 17 ans, le compte n'est ouvert qu'après accord enregistré du parent ou du représentant légal.

Une fois le compte ouvert, un joueur présente son profil sportif, publie des vidéos et suit d'autres profils. Les vidéos sont examinées par un modérateur avant d'apparaître dans le fil public.

Les clubs, les recruteurs et les agents publient des offres et des évènements, et recherchent des joueurs par nationalité, par année de naissance et par disponibilité. Seules les fiches complètes et publiques apparaissent dans ces résultats. Le profil d'un joueur mineur n'y figure qu'après validation par l'administration.

La messagerie relie les comptes déjà en relation sur la plateforme.

L'âge minimum est de 13 ans. Un parent peut à tout moment demander la modification ou le retrait des autorisations de son enfant en écrivant à support@adfoot.org.

Conditions d'utilisation : https://adfoot.org/legal/terms.html
Politique de confidentialité : https://adfoot.org/legal/privacy-policy.html
Suppression de compte : https://adfoot.org/legal/account-deletion.html
```

### Description complete, fiche par defaut (anglais)

Avant : `Adfoot is a professional football network in Mali.`
Apres : `Adfoot is a professional network for African football.`

Texte complet a coller (copie de confort dans
`artifacts/store-copy-1.0.8+54/description-en.txt`, non suivi par git) :

```
Adfoot is a professional network for African football. It connects players, clubs, scouts, and agents in a verified environment.

Accounts are created by the Adfoot administration after identity verification. The application does not offer open registration: account requests are made on adfoot.org. For players aged 13 to 17, an account is only opened after registered consent from a parent or legal guardian.

Once an account is opened, a player presents their sporting profile, posts videos, and follows other profiles. Videos are reviewed by a moderator before appearing in the public feed.

Clubs, scouts, and agents post offers and events, and search for players by nationality, year of birth, and availability. Only complete and public profiles appear in these results. A minor player's profile only appears after validation by the administration.

The messaging system connects accounts already linked on the platform.

The minimum age is 13. A parent can request to modify or withdraw their child's permissions at any time by writing to support@adfoot.org.

Terms of Use: https://adfoot.org/legal/terms.html
Privacy Policy: https://adfoot.org/legal/privacy-policy.html
Account Deletion: https://adfoot.org/legal/account-deletion.html
```

### Ce qui n'est pas change, et le sait

L'image de la fiche (feature graphic) porte « pour le football malien »
grave dedans, ecrit par `scripts/make-feature-graphic.ps1` ligne 78. Decision
prise le 18 octobre 2026 : on ne la regenere pas dans cette passe. Le mot
« Mali » reste donc visible sur l'image de la fiche alors que la description
dit « africain ». La correction est d'un mot dans ce script, suivie d'une
regeneration et d'un televersement d'asset, si l'incoherence devient genante.

L'adresse de l'editeur affichee par Play (« Mali ») est une donnee de compte
developpeur, pas de la copie : elle ne se change pas ici et n'a pas a l'etre.

## Verifie pour ce build

| Controle | Commande | Resultat, 18 octobre 2026 |
| --- | --- | --- |
| Analyse statique | `flutter analyze` | `No issues found!` |
| Tests | `flutter test` | `1056 tests passed`, code de sortie 0 |
| Temoins relus pour le bon numero | `test/aab_content_expectations_guardrails_test.dart` | passe, `forVersionCode` 54 = `versionCode` du pubspec |
| Parite FR/EN des cles GetX | `test/video_ui_translations_test.dart` | passe, les six cles resolvent dans les deux langues et non vers la cle nue |
| Chaines traduites rendues | audit manuel | `app_en.arb` et `app_fr.arb` a 819 cles chacun, aucune manquante, aucune prose francaise cote anglais |

Les codes de sortie ont ete lus dans un fichier, jamais au travers d'un
`| tail` : un pipe rend le statut de `tail`, pas celui de `flutter test`.

### Fausses pistes ecartees pendant l'audit de traduction

- `lib/utils/validator.dart` porte trois messages en francais et n'est importe
  nulle part : code mort, invisible pour l'utilisateur.
- 12 des 14 constantes de `VideoUiStrings` qui ne passent pas par `.tr` ne
  sont appelees nulle part.
- `missingShareUrlLog` part dans `logActionFailure`, pas a l'ecran. Le message
  affiche a cote, `missingShareUrl`, est bien traduit.

## Reste a faire, dans l'ordre

1. Construire le bundle : `npm.cmd run release:android:gate:build`
2. Verifier que le bundle porte ce checkout :
   `npm.cmd run release:android:contents:check`
3. Play Console, piste Production : televerser, coller les quatre textes
   ci-dessus, deployer a 100 %
4. Ne toucher a rien cote iOS avant la fin de la revue du `53`
