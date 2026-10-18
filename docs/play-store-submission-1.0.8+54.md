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

**Une seule fiche existe, en francais, et elle est la fiche par defaut.**
Constate le 18 octobre sur la page d'edition : le selecteur de langue ne
propose que le francais, et la soumission 3 nommait la meme cible deux fois,
"French (France) - fr-FR" puis "Default store listing".

Correction d'une erreur d'analyse du meme jour, consignee parce qu'elle a
produit un faux defaut dans la premiere version de ce document : la
description anglaise lue sur play.google.com n'etait pas une fiche anglaise,
c'etait la traduction automatique que Google sert aux visiteurs non
francophones. Google traduit la description mais pas le champ Nouveautes, ce
qui expliquait le melange observe. Rien n'etait casse ; il y a un choix a
faire, ce qui n'est pas la meme chose.

### Nouveautes, fiche fr-FR

A coller tel quel, un paragraphe par ligne.

```
Adfoot, le réseau du football africain.

• Les vidéos reprennent là où vous les avez laissées.
• L'ajout d'un CV explique un refus dans votre langue.
• Version anglaise complète pour les utilisateurs qui ont choisi l'anglais.

Les comptes sont créés par l'équipe Adfoot après vérification. La demande de compte se fait sur adfoot.org.
```

### Description complete, fiche fr-FR

Seule la premiere phrase change. Le reste est repris mot pour mot de la
version en ligne, qui est exacte sur les comptes, l'age minimum et l'accord
parental, et qu'il ne faut pas reecrire.

Avant : `Adfoot est un réseau professionnel du football au Mali.`
Apres : `Adfoot est un réseau professionnel du football africain.`

Deux changements dans ce texte, et deux seulement. Le passage de "au Mali" a
"africain", verifie par les compteurs : le champ Play affichait 1403
caracteres, le texte substitue en comptait 1404, soit exactement l'ecart entre
"au Mali" (7) et "africain" (8). Puis l'alignement du vocabulaire decrit
ci-dessous, qui ramene le total a 1395. Aucune autre phrase n'a bouge, et la
console l'a confirme en rendant la valeur precedente a chaque ecriture.

```
Adfoot est un réseau professionnel du football africain. Il réunit les joueurs, les clubs, les recruteurs et les agents dans un cadre vérifié.

Les comptes sont créés par l'équipe Adfoot après vérification de l'identité. L'application ne propose pas d'inscription libre : la demande de compte se fait sur adfoot.org. Pour un joueur de 13 à 17 ans, le compte n'est ouvert qu'après accord enregistré du parent ou du représentant légal.

Une fois le compte ouvert, un joueur présente son profil sportif, publie des vidéos et suit d'autres profils. Les vidéos sont examinées par un modérateur avant d'apparaître dans le fil public.

Les clubs, les recruteurs et les agents publient des offres et des évènements, et recherchent des joueurs par nationalité, par année de naissance et par disponibilité. Seules les fiches complètes et publiques apparaissent dans ces résultats. Le profil d'un joueur mineur n'y figure qu'après validation par l'équipe Adfoot.

La messagerie relie les comptes déjà en relation sur la plateforme.

L'âge minimum est de 13 ans. Un parent peut à tout moment demander la modification ou le retrait des autorisations de son enfant en écrivant à support@adfoot.org.

Conditions d'utilisation : https://adfoot.org/legal/terms.html
Politique de confidentialité : https://adfoot.org/legal/privacy-policy.html
Suppression de compte : https://adfoot.org/legal/account-deletion.html
```

### Defaut de la description courte

Le champ compte 64 caracteres la ou le texte rendu sur le Store en fait 62, et
la valeur copiee depuis la console montre "du" suivi de trois espaces. Deux
signaux concordants : la valeur enregistree porte deux espaces en trop. Le
HTML les ecrase a l'affichage web, ce qui les rend invisibles sur
play.google.com, mais l'application Play sur Android rend le texte brut. A
remettre en espace simple.

Valeur correcte : `Profils, vidéos et mises en relation pour talents du football.`

### Un acteur, un seul mot : l'equipe Adfoot

La fiche disait "l'administration Adfoot" et "validation par l'administration",
l'application dit "l'equipe Adfoot" et "the Adfoot team"
(`publicSignupDisabledMessage`), et la fiche anglaise redigee ici disait
"the Adfoot team". Trois surfaces, deux mots, un seul acteur. La fiche s'aligne
sur le produit, pas l'inverse : les deux occurrences francaises passent a
"l'equipe Adfoot". Le sens ne bouge pas, seul le nom de celui qui agit est
rendu identique partout, y compris dans la phrase sur les profils mineurs.

### Fiche anglaise, si elle est ajoutee

Non requise pour livrer le 54. C'est un engagement d'entretien : chaque
modification future de la fiche devra etre faite deux fois, sinon l'anglaise
se perime. En revanche elle ne coute aucun visuel, la page d'edition l'ecrit
elle-meme : les langues sans graphismes propres reprennent ceux de la langue
par defaut.

Ne pas utiliser "Import translations with AI" pour ce texte. Le vocabulaire
footballistique est precisement ce que la traduction automatique manque, c'est
le bug corrige dans l'application le 17 octobre, et la machine le refait ici :
elle rendait "recruteurs" par "scouts" alors que l'application dit
"Recruiter" (profileRoleRecruteur) et enumere "Visible to clubs, recruiters,
and agents.". Le texte ci-dessous est relu contre app_en.arb terme a terme, et
il porte des mentions sur les mineurs et l'accord parental qu'une machine ne
doit pas paraphraser.

Nom de l'application : `Adfoot`

Description courte (54/80) :

```
Profiles, videos, and connections for football talent.
```

Description complete (1223/4000) :

```
Adfoot is a professional network for African football. It connects players, clubs, recruiters, and agents in a verified environment.

Accounts are created by the Adfoot team after identity verification. The app does not offer public sign-up: account requests are made on adfoot.org. For players aged 13 to 17, an account is opened only once a parent or legal guardian has given recorded consent.

Once an account is open, a player presents their football profile, posts videos, and follows other profiles. Videos are reviewed by a moderator before they appear in the public feed.

Clubs, recruiters, and agents post offers and events, and search for players by nationality, year of birth, and availability. Only complete, public profiles appear in those results. A minor's profile appears only after review by the Adfoot team.

Messaging is available between accounts that are already connected on the platform.

The minimum age is 13. A parent can ask at any time to change or withdraw their child's permissions by writing to support@adfoot.org.

Terms of Use: https://adfoot.org/legal/terms.html
Privacy Policy: https://adfoot.org/legal/privacy-policy.html
Account Deletion: https://adfoot.org/legal/account-deletion.html
```

Nouveautes (204/500) :

```
Adfoot, the network for African football.

• Full English translation, including positions, strong foot and contract status.
• Videos resume where you left off.
• CV upload messages now appear in English.

Accounts are created by the Adfoot team after verification. Account requests are made on adfoot.org.
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

## Soumis le 18 octobre 2026

Quatre changements envoyes en une soumission, etat `Changes in review` :

| Element | Description |
| --- | --- |
| Production | `54 (1.0.8)`, Start full rollout |
| Store listings `en-US` | Add language, nom et informations requises |
| Store listings `fr-FR` | Change short description |
| Store listings `fr-FR` | Change full description |

`Managed publishing` est **desactive** : l'approbation met la version en ligne
sans autre geste. Le `52` reste telechargeable pendant tout l'examen.

Le bundle attache a la version a ete relu dans la console avant envoi :
`New app bundles` porte `54 (1.0.8)`, API 24+, target SDK 36, 3 ABIs, ce qui
correspond au bundle construit ici. Une table voisine affiche `52 (1.0.7)`
sous le titre `54 (1.0.8)` : c'est `Deactivated app bundles`, le 52 y figure
parce qu'il est remplace. Ne pas lire cette ligne comme une erreur de contenu.

Taille reellement livree, donnee par la console : **15,6 Mo en nouvelle
installation, 4,76 Mo en mise a jour**, pour un `.aab` de 74 Mo. Play decoupe
par ABI et par densite, ce que le commentaire `ndk` de `android/app/build.gradle`
explique deja.

### A verifier une fois en ligne

1. La fiche fr-FR affiche `du football africain` et la description courte sans
   espaces doubles
2. La fiche en-US existe et n'est plus une traduction automatique
3. Les nouveautes s'affichent dans les deux langues
4. Les appareils en `52` passent bien en `54`

### A ne pas faire pendant l'examen

- Ne pas rouvrir le questionnaire IARC : les reponses n'ont pas change, rien
  dans le `54` ne touche au contenu classifiable
- Ne rien reconstruire ni renvoyer cote iOS : le `53` est en revue chez Apple
  et un nouveau televersement l'annulerait. Le prochain build iOS part du `55`
- Ne pas modifier la fiche : une edition pendant l'examen ouvre une soumission
  concurrente

### Reste ouvert

**Fusionner `master` une fois le 54 publie.** Decide le 18 octobre 2026.
`origin/master` est a `0722700`, soit le contenu du build 52 : il est un
ancetre direct de cette branche, donc l'avance rapide se fera sans conflit.
Le choix d'attendre est deliberatif et pas de la paresse : tant que le 52 est
la version en ligne, un `master` qui porte le 52 decrit la verite. Le 54 n'est
pour l'instant qu'une demande, et si Google la refusait, `master` resterait
propre. Des que la publication est effective, la fusion devient la description
exacte de la production.

**L'image de la fiche.** Elle porte toujours `pour le football malien`
(`scripts/make-feature-graphic.ps1` ligne 78) alors que la description dit
desormais `africain`. L'incoherence est maintenant visible sur la meme page.
Un mot dans ce script, une regeneration, un televersement d'asset, dans une
soumission separee apres la mise en ligne.
