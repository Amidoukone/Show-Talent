# Ce qui reste avant les soumissions Play Store et App Store

Relevé du 15 octobre 2026, destiné à reprendre le travail sans rien redécouvrir.
Tout ce qui est marqué fait a été vérifié, pas supposé.

## Où en est le système, en une page

| Surface | État | Déployé |
| --- | --- | --- |
| Règles Firestore et Storage | identiques au dépôt, 44/44 index READY, TTL actifs | oui, 2026-10-10 |
| Cloud Functions | 59 fonctions, âge minimum 13 ans appliqué | oui, 2026-10-15 |
| Site public adfoot.org | refait, images et logo à jour | oui, 2026-10-15 |
| Pages légales, 6 pages FR et EN | version 1.2, en vigueur le 15 octobre | oui, 2026-10-15 |
| Portail admin | aligné sur 13 ans, calcul d'âge dédupliqué | oui, 2026-10-15 |
| Build mobile Android | `1.0.7+52`, AAB signé, contenu prouvé par témoins | construit, non soumis |
| Build mobile iOS | `1.0.7+52` au déclenchement, Codemagic manuel | non |

Les deux dépôts sont propres et poussés sur
`release/production-device-tests-2026-10-05`.

## 1. Bloquants : sans eux, le rejet est certain

### 1.1 Le compte de démonstration App Review

C'est le seul élément dont l'absence provoque un rejet garanti, des deux côtés.
`publicSelfSignupRoles` est la liste vide : un relecteur qui ouvre l'application
n'atteint rien sans identifiants. C'est le rejet Guideline 2.1 standard, et il
coûte un cycle de revue complet.

Ordre exact, parce qu'un détail y détruit silencieusement une soumission :

1. **Créer le compte par le portail admin** (`provisionManagedAccount`),
   **jamais** dans la console Firebase Auth. `cleanupUnverifiedAccounts` tourne
   toutes les 24 h et supprime les comptes de plus de 3 jours. L'exemption ne
   s'applique qu'aux comptes portant `createdByAdmin === true`, que seul le
   portail écrit. Un compte créé à la main disparaît au milieu de la revue, le
   relecteur ne voyant qu'un login invalide.
2. **Rôle `joueur`.** C'est celui qui atteint le plus de surface, et c'est le
   parcours que les captures d'écran promettent.
3. **Profil déjà rempli** : nom, photo, poste, et au moins une vidéo approuvée.
   Un compte qui se connecte puis affiche des écrans vides provoque un rejet 2.1
   pour une autre raison.
4. **Garder un second compte** le temps de montrer la messagerie, avant de
   supprimer les comptes de test.
5. **Après le ménage**, relancer `npm run legacy:residue:gate:production` et
   `npm run backend:parity:check:production`.
6. **Deux vérifications distinctes avant de soumettre** : que
   `createdByAdmin == true`, `emailVerified == true`, `estActif == true` et
   `role == "joueur"` sur son document `users` ; et que la connexion fonctionne
   **depuis le build soumis**, sur un appareil n'ayant jamais eu de session.

Le texte des notes de revue à coller est prêt dans `../store-compliance.md`,
section « Review notes text to paste ».

### 1.2 Play Console, App access

Encore sur « tout est accessible » par défaut, ce qui est une déclaration fausse
pour cette application. Passer à « accès restreint » et renseigner les
identifiants du compte de démonstration.

### 1.3 App Store Connect, Sign-In Required

Cocher la case dans App Review Information et renseigner les mêmes identifiants.

## 2. Déclarations à remplir dans les consoles

- **Play Console, audience : 13 ans et plus, et rien de plus jeune.** C'est ce
  qui matérialise le bénéfice du passage à 13 ans fait le 15 octobre. Choisir
  une tranche inférieure réinstaure toute la Families Policy, c'est-à-dire un
  consentement parental vérifiable et un moyen pour l'adulte de gérer les
  fonctions sociales.
- **Apple, étiquettes App Privacy** et questionnaire de classification d'âge.
- **Play, formulaire Data safety.** Noter qu'une référence de paiement est
  désormais enregistrée, déclarée dans la politique de confidentialité.
- **Aucun achat intégré**, des deux côtés. C'est vrai et le code le protège :
  l'application n'affiche aucun prix, n'offre aucun moyen de payer et ne renvoie
  vers aucun. Ne jamais ajouter de prix ni de bouton de paiement à
  l'application, sous peine de rendre cette déclaration fausse.

## 3. À faire valider hors du code

### 3.1 La clause de part sur contrat, par un conseil

**C'est le point le plus sérieux du dossier.** Les CGU prévoient qu'Adfoot peut
percevoir une part sur un contrat conclu grâce à son intermédiation. Prélever
une part sur le contrat d'un joueur relève des FIFA Football Agent Regulations,
qui réservent l'activité aux agents licenciés et interdisent toute rémunération
liée à un mineur. La plateforme accueille des joueurs de 13 à 17 ans.

La clause publiée est rédigée prudemment : convention écrite distincte, acceptée
avant tout engagement, refusable sans perdre son compte, et aucune part lorsque
les règles l'interdisent pour un mineur. Mais le principe lui-même doit être
validé.

Deux points restent à préciser dans les CGU une fois arrêtés : ce que contient
exactement l'accompagnement de base inclus dans les 15 000 FCFA, et l'assiette
de la part sur un contrat. Le texte actuel renvoie à une convention distincte,
ce qui est exact mais vague.

### 3.2 Le registre des visuels

`player-image-release-register.md` porte la confirmation de l'accord parental
avec sa date. Le tableau de traçabilité reste à remplir depuis les accords
conservés en privé : personnes visibles, âge vérifié, droits du photographe,
étendue des usages, date et référence de preuve. L'empreinte de contenu portée
par chaque nom de fichier (`player-05.969f9661.jpg`) sert de référence interne
stable pour désigner un visuel.

## 4. Vérifications sur appareil réel

- **Suivre et ne plus suivre**, et qu'une suppression de compte ne laisse pas de
  compteur de suiveurs décalé. C'est le reliquat de la fermeture de la migration
  `public_profiles` du 13 octobre : l'absence de résidu est mesurée, le
  comportement ne l'est pas.
- **Les pages légales sur téléphone**, en français et en anglais, avec la
  bascule de langue, le bouton WhatsApp du site et le formulaire de contact.
- **La connexion du compte de démonstration depuis le build soumis.**

## 5. Optionnel, à décider

- ~~**Armer la porte d'acceptation des CGU**~~ Décidé le 15 octobre : on arme
  avant les soumissions, pour que la version soumise soit celle qui recueille
  réellement le consentement. Reste à exécuter, et dans cet ordre, parce que
  l'ordre porte le risque :
  1. `+51` installé sur les appareils de test, pas seulement construit.
  2. Compte de démonstration créé par le portail admin.
  3. `npm run legal:gate:arm:production`.
  4. Accepter les CGU une fois sur le compte de démonstration, puis
     `npm run review:account:check:production -- --email <adresse>` doit
     afficher `READY`.

  Les étapes 1 et 2 ne sont pas de la prudence décorative : armer sur un parc
  en `+50` recueille un consentement devant deux promesses fausses, et sauter
  l'étape 4 met l'écran de consentement devant le relecteur avant l'application.
  Procédure complète dans `../store-compliance.md`, section « Activating the
  acceptance gate ».
- ~~**Un nouveau build mobile.**~~ Fait le 15 octobre après-midi, voir la
  section « Le build 1.0.7+51 » ci-dessous.
- **La clé `.p8` APNs sur `adfoot-staging`.** Indécidable sans build staging
  installé, et non bloquant : la production est prouvée, un appareil iOS a
  obtenu son jeton sous `1.0.7+49`.
- **Retirer `firestore.transition.rules`.** Quatre endroits couplés, aucun
  préalable au lancement, à faire après les soumissions.
- **Préciser la région de la base et du stockage** dans la section 5 des deux
  politiques. Seule la région des Cloud Functions (`europe-west1`) est
  documentée ; le texte actuel est exact sans être précis. **Reporté après les
  soumissions, décidé le 15 octobre.** La raison n'est pas la paresse : toucher
  les politiques maintenant obligerait à trancher si cela vaut une version 1.3,
  et une 1.3 redéclencherait l'écran de consentement pour tout le parc en
  invalidant l'acceptation déjà faite sur le compte de démonstration, en pleine
  revue. Préciser un fait déjà vrai ne vaut pas ce risque avant les
  soumissions.

## Le build 1.0.7+51, et un ordre à respecter

Construit le 15 octobre après-midi. `flutter analyze` ne signale rien, les
1042 tests passent, le gate de readiness Play Store passe, et l'AAB signé est
archivé en `artifacts/android/adfoot-production-20261015T151113Z.aab`
(versionCode 51, versionName 1.0.7, 70,65 Mo). iOS passe son propre gate, avec
le seul avertissement attendu : `Podfile.lock` est généré sur macOS par
Codemagic. Le workflow `ios-production` n'a pas de déclencheur automatique, il
se lance à la main depuis Codemagic et publie sur TestFlight. Les deux
plateformes prennent leur numéro de build dans `pubspec.yaml`, donc `+51` des
deux côtés.

### Pourquoi ce build n'est pas un détail de confort

Mesuré, pas supposé : le build `1.0.7+50` **contient** l'écran d'acceptation des
CGU, et cet écran y affiche encore « Gratuit pour les joueurs » et « sans
commission ». Les deux sont devenus faux en version 1.1 des conditions, qui
nomme les 15 000 FCFA et autorise une part sur contrat. Ce build n'a par
ailleurs aucune URL anglaise, donc un utilisateur en anglais atterrit sur le
texte français.

Conséquence sur l'ordre, et c'est la seule chose à retenir : **armer la porte
d'acceptation pendant que le parc est en `+50` ferait cocher « j'accepte »
devant un écran qui contredit le document accepté**, et enregistrerait ce
consentement. Distribuer `+51` d'abord, armer ensuite.

Le contrôle de contenu du bundle le prouve désormais mécaniquement plutôt que
sur parole. `scripts/aab-content-expectations.json` porte deux témoins
`mustNotContain`, « Gratuit pour les joueurs » et « sans commission », qui font
échouer le contrôle si un bundle les porte encore, et deux témoins
`mustContain` pour le texte corrigé et le routage anglais. Vérifié sur l'AAB
du 51 : les deux premiers absents, les deux seconds présents.

### Le premier build iOS a échoué, et ce n'était pas le push

Relevé le 15 octobre à 15h47. App Store Connect a renvoyé un 409
`ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE`, avec
`previousBundleVersion = 49`. Le push était bon : Codemagic avait construit la
branche `master` au commit `8471d77`, où `pubspec.yaml` porte `1.0.7+49`, une
version déjà téléversée. La branche de release portait le `+51` depuis une
heure.

Les workflows de `codemagic.yaml` n'ont aucun déclencheur automatique, donc la
branche est choisie dans le dialogue de démarrage, et `master` en est le défaut.
C'est ce qui rend le retard de `master` dangereux plutôt que seulement
désordonné : un build lancé sans y penser produit un bundle d'une version déjà
consommée, et l'échec arrive quinze minutes plus tard, à la publication, loin de
sa cause.

`master` a donc été avancé en avance rapide jusqu'au même commit que la branche
de release, après avoir vérifié qu'aucune des deux références, locale ou
distante, ne portait un commit absent de la release. Les deux branches pointent
désormais le même commit et `master` porte `1.0.7+51`. **Tant que `master` reste
à jour, le défaut de Codemagic est correct ; s'il décroche à nouveau, le même
échec reviendra.**

### Les quatre tirets cadratins, retirés et livrés dans le 52

Relevé le 15 octobre en lisant les textes de l'écran de consentement. Quatre
occurrences de U+2014 dans la copie livrée : `termsVersionWithDateLabel` en
français et en anglais, donc sur la ligne de version de l'écran que le relecteur
verra, et `talentSearchResultsCountMany` dans les résultats de recherche de
joueurs. Corrigées dans les `.arb` et la localisation régénérée, les quatre
remplacées par une virgule.

Décision du 15 octobre : pas de build pour cela seul. L'écart entre la source
et le binaire a disparu de lui-même le 16, quand le `+51` s'est révélé
insoumettable et qu'il a fallu construire le `+52` : celui-ci porte la
correction. Il ne reste donc aucune divergence.

Note de méthode, parce qu'elle a failli coûter le relevé : chercher ce caractère
par une séquence d'échappement ANSI-C dans `grep` ne fonctionne pas dans le shell
de cette machine. Le motif ne reçoit pas les bons octets, la recherche répond
silencieusement zéro, et cela se lit comme une absence. Même cause pour les
antislashs passés à un interpréteur par un document en ligne ici : ils arrivent
dédoublés. Compter en Python sur le fichier décodé en UTF-8.

### Un numéro de build téléversé est consommé pour toujours

Relevé le 16 octobre, au moment de créer la release de production. Play a
refusé l'AAB du `+51` : « Version code 51 has already been used ». Le `51`
avait été téléversé en **test interne**, et le même numéro avait été consommé
côté iOS. Un numéro de build ne se réutilise sur aucune piste, pas même après
suppression d'une release de test.

Conséquence pratique, à garder en tête pour chaque cycle : **ne pas téléverser
un candidat en test interne si l'on compte soumettre ce même binaire en
production.** Soit on teste le binaire exact qui sera soumis et on accepte de
le reconstruire, soit on réserve un numéro par destination. Le coût n'est pas
le build, qui dure un quart d'heure, mais la réinstallation sur les appareils
et la reprise des vérifications sur appareil réel.

Le `+52` corrige donc le `+51` sans rien changer d'autre que le numéro et les
quatre tirets cadratins déjà corrigés en source la veille.

## Reprise du 16 octobre : la toute première action

**Ne reconstruisez pas.** Le bundle `52` est déjà dans la bibliothèque Play,
téléversé le 16 octobre à 01h06, statut `Inactive`, catalogue passé de 32 à 33
versions. Le téléversement avait réussi ; c'est le brouillon de release qui a
été perdu, pas le binaire. L'erreur « Version code 52 has already been used »
venait d'une seconde tentative sur le même fichier, que Play refuse comme
doublon.

Dans **Create new release**, il faut donc choisir le bundle **depuis la
bibliothèque** au lieu d'en téléverser un. Puis les notes de version en
français, puis `Save`, sans envoyer en revue.

Leçon de la soirée, à ne pas repayer : **chaque tentative de téléversement
consomme le numéro**, qu'elle aboutisse à une release ou non. Et il ne faut pas
piloter la console depuis deux endroits à la fois, même dans des onglets
distincts : c'est une application à session unique.

### État de la Play Console au 16 octobre, 01h

| Élément | État |
| --- | --- |
| Déclarations App content | 11 actionnées, « Need attention » vide |
| Sign-in details | `amidoudev@gmail.com`, vérifié dans la console |
| Target audience | 13-15, 16-17, 18+, restriction des mineurs levée |
| Data safety | enregistrée le 16 octobre |
| Pays de production | 179, tous |
| Fiche Play | `fr-FR` uniquement, Live depuis le 23 juillet |
| Bundle 52 | dans la bibliothèque, `Inactive` |
| Release de production | **à créer**, piste encore Inactive |
| Changements en attente de revue | 3, plus la release à venir |

L'envoi en revue portera la release **et** les trois changements d'un seul
coup. Un rejet sur l'un fait repartir l'ensemble.

### Côté iOS, rien n'est fait

Seuls des tests internes TestFlight ont eu lieu. Il reste le parcours complet :
App Privacy, classification d'âge, App Review Information avec `Sign-In
Required`, et le déclenchement de `ios-production` sur Codemagic, qui lira
`1.0.7+52` dans `pubspec.yaml`. Le `51` y a été consommé aussi.

### Ajouter l'anglais à la fiche Play, plus tard

La fiche ne possède que `fr-FR`. Une balise `<en-US>` dans les notes de version
serait rejetée. Ajouter la langue passe par **Manage languages** dans le
sélecteur de la fiche, et oblige à fournir nom, description courte de 80
caractères et description longue de 4000 dans cette langue ; les visuels
retombent sur ceux de la fiche par défaut. C'est une modification de fiche :
aucun build, revue séparée, possible après publication.

## Trois commandes ajoutées le 15 octobre

Elles remplacent autant de manipulations en console, où rien ne laisse de trace
et où une faute de frappe est silencieuse.

| Commande | Ce qu'elle fait |
| --- | --- |
| `npm run legal:gate:status:production` | Lit `config/legal`, montre le document qu'elle écrirait, vérifie que les quatre pages légales répondent 200. N'écrit rien. |
| `npm run legal:gate:arm:production` | Même chose puis écrit, et refuse d'armer si une des quatre pages ne répond pas 200. |
| `npm run review:account:check:production -- --email <adresse>` | Dit si le compte de démonstration est remettable à un relecteur. |

Le vérificateur de compte existe pour une raison précise. `MANAGED_ROLES` dans
`functions/src/cleanup.ts` vaut `{admin, club, recruteur, agent}` : **`joueur`
n'y est pas**. Le compte de démonstration doit être un `joueur`, donc il ne
survit à `cleanupUnverifiedAccounts` que par `createdByAdmin === true`, sans
aucun filet. Cette condition est invisible à la lecture du compte, et c'est
exactement celle qui détruit une soumission au quatrième jour. La commande lit
ce booléen, et dans le même passage ce qu'un relecteur rencontrerait dans
l'ordre : connexion possible, compte actif, profil rempli plutôt qu'écrans
vides, et version des CGU déjà acceptée si la porte est armée.

### La porte est armée depuis le 15 octobre

`config/legal` a été créé en production avec `requiredVersion: "1.2"`,
`effectiveOn: "15 octobre 2026"` et les quatre URL, après que le contrôle
préalable a confirmé les quatre pages légales à 200. L'ordre documenté plus haut
a été respecté : le `+51` était installé sur Android et sur iOS, et le compte de
démonstration existait et était vérifié. Pour défaire :
`npm run legal:gate:disarm:production`.

### Le vérificateur de compte lisait un champ périmé

Il déclarait le compte de démonstration incomplet pour un poste absent, alors
que le profil portait `positionCodes: ["AM", "RW"]`. Il lisait `position`, un nom
qui n'apparaît nulle part dans `PlayerFootballProfile` : les faits
footballistiques sont aplatis au premier niveau du document, et le nom du modèle
est `positionCodes`, présent dans `writableFieldPaths`. `playerProfile` n'existe
pas davantage sur un document réel.

C'est le pire mode de défaillance pour un contrôle de pré-soumission, parce
qu'il envoyait corriger un écran déjà correct. Un contrôle qui crie au loup sur
du travail fini finit par être ignoré le jour où il a raison. Corrigé et
remesuré : les deux comptes affichent `READY` avant armement, et signalent
l'acceptation manquante après, ce qui est le comportement attendu.

## Ce qui a été fait le 14 et le 15 octobre

Pour mémoire, parce que plusieurs de ces points étaient des défauts silencieux.

- Les CGU renvoyaient une **erreur 404** depuis le courriel d'activation et
  depuis l'écran Réglages de l'application. Six pages légales publiées en FR et
  EN, et trois garde-fous ajoutés pour que ce ne soit plus possible.
- Le site promettait ce que le produit ne fait pas : une inscription libre qui
  n'existe pas, du coaching exclu par les CGU, une messagerie « sans
  intermédiaire » alors que les mineurs sont en contact médié. Refait.
- Les visuels pesaient 22 Mo, ramenés à 1,4 Mo. Le logo du site datait d'une
  marque abandonnée, régénéré depuis celui de l'application.
- Les CGU affirmaient que l'accès des joueurs était **gratuit**. Corrigé en
  version 1.1 le jour même, avec le prix réel.
- L'âge minimum est passé de 12 à 13 ans, ce qui supprime la Families Policy.
  Appliqué côté serveur, dans les textes publiés et dans le portail admin, où il
  a révélé un sélecteur de date resté à 12.

Relevés détaillés : `legal-publication-2026-10-14.md`,
`site-pub-redesign-2026-10-14.md`, `decisions-lancement-2026-10-13.md`.

## Ce qui a été fait le 16 octobre au matin

### Le compte de revue a survécu à la nuit, mesuré et non supposé

`npm run review:account:check:production -- --email amidoudev@gmail.com`
répond `READY` : rôle `joueur`, `createdByAdmin: true` donc exempté de
`cleanupUnverifiedAccounts`, `emailVerified`, `estActif`, profil rempli
(`positionCodes: AM, RW`, photo, 1 vidéo approuvée sur 1) et CGU 1.2
acceptées. C'est la vérification à refaire chaque matin tant que la revue
n'est pas passée, parce que le ménage tourne toutes les 24 h.

### Un bloquant de policy, découvert et déjà résolu par ce build

La console affichait « App updates with these issues will be rejected », en
vigueur depuis le 31 août 2026 : **App must target Android 16 (API level 36)
or higher**. Vérifié des deux côtés plutôt que supposé : le manifeste
empaqueté dans le bundle porte `targetSdkVersion="36"`
(`build/app/intermediates/packaged_manifests/productionRelease/`), et la Play
Console elle-même affiche `Target SDK 36` pour le bundle 52 dans l'App bundle
explorer. L'avertissement porte sur la version publiée en juillet. Cette
release le corrige au lieu de buter dessus.

### La release de production

Le brouillon n'était pas perdu : la piste portait déjà un `Draft release`, ce
qui désactivait « Create new release ». Il a suffi de l'ouvrir, d'y ajouter le
bundle 52 **depuis la bibliothèque**, de saisir les notes de version et
d'enregistrer. Statut `Ready to release`, `Start full rollout`, 100 %.

Deux décisions prises ce matin, assumées :

- **Managed publishing reste OFF.** Google publiera dès l'approbation, sans
  redemander, à l'heure qu'il voudra.
- **Déploiement à 100 %**, et non progressif. Sur 11 installations et 7
  utilisateurs actifs, un palier ne mesure rien d'exploitable.

Notes de version en `fr-FR`, 495 caractères, sans tiret cadratin. Elles
décrivent une **première mise en ligne**, pas une mise à jour : la piste
production était `Inactive` et l'application n'avait jamais quitté les tests.

### La fiche Play, refaite parce qu'elle mentait

C'est la trouvaille de la matinée, et elle vient d'une question posée sur les
captures d'écran. La fiche datait du 23 juillet et promettait ce que
l'application ne fait pas.

**« Avec Adfoot, les utilisateurs peuvent créer un profil ».**
`publicSelfSignupRoles` est la liste vide (`account_role_policy.dart:3`) et
l'écran d'inscription ne contient aucun formulaire. C'est la même fausse
promesse qui avait imposé la refonte du site public le 14 octobre, restée ici.
Un relecteur qui lit cette phrase, ouvre l'application et ne trouve aucun
moyen de créer un compte tient le motif de rejet le plus mécanique qui soit.

**« coachs »**, dans la description et dans le visuel de couverture. Aucun
rôle `coach` n'est provisionnable.

Description réécrite, 1403 caractères, chaque affirmation tracée au code et
non à la documentation. Au passage, une affirmation a été corrigée **parce que
le code la contredisait** : la recherche de joueurs ne filtre pas par poste,
mais par nationalité, année de naissance et disponibilité.

Captures et visuel de couverture refaits : voir
`player-image-release-register.md`, section du 16 octobre, qui porte la
provenance de chaque image, les deux retouches et leur motif, et la
confirmation datée de l'accord parental pour la capture montrant des mineurs.

**AI asset declaration : « Don't label assets ».** Aucun modèle génératif n'a
produit de pixel. Le visuel assemble le logo existant et du texte dans une
police ; les deux retouches déplacent des glyphes existants ou en tracent dans
la police de l'application. La déclaration de Google vise les contenus
synthétiques, pas la retouche déterministe.

### Un défaut mineur, réel, à traiter après les soumissions

`eventParticipantsCountLabel` et `eventViewsCountLabel` sont des chaînes
plates : l'écran affiche « 1 participants » et « 1 vues », visible sur la
capture `04-evenements`. Ce n'est pas un cas isolé : `app_fr.arb` ne contient
**aucun** pluriel ICU, zéro occurrence de `plural`. L'application n'accorde
jamais ses compteurs. Corriger demande d'introduire les pluriels ICU sur un
ensemble de chaînes, ce qui ne se fait pas au milieu d'une soumission.

### État du lot au moment d'écrire

8 changements en attente, qui partiront d'un seul bloc :

| # | Élément | Contenu |
| --- | --- | --- |
| 1 | Production | `52 (1.0.7)`, full rollout |
| 2 | Countries/regions | +177 pays |
| 3 | Countries/regions | reste du monde |
| 4 | Store listing fr-FR | description complète |
| 5 | Store listing fr-FR | captures d'écran |
| 6 | Store listing fr-FR | visuel de couverture |
| 7 | App content | audience 13 ans et plus |
| 8 | App content | Data safety |

Un rejet sur l'un fait repartir l'ensemble.

### Deux pièges d'outillage, pour ne pas les repayer

**Le sélecteur de fichiers natif bloque l'onglet.** La Play Console crée son
`input[type=file]` à la volée, il n'existe pas dans le DOM avant le clic. La
parade retenue : intercepter `HTMLInputElement.prototype.click` pour les
champs de type fichier, rattacher le champ au document et le rendre visible,
au lieu d'ouvrir la boîte native.

**Les antislashs ne survivent pas à un document en ligne ici.** Déjà consigné
pour `grep`, vérifié à nouveau en écrivant un `.ps1` : le chemin
`C:\flutter\bin\cache\...` est arrivé sous la forme
`C:lutterin\cachertifacts...`, les séquences ayant été interprétées comme
des échappements. Utiliser des barres obliques, que les API Windows
acceptent. Même famille de piège : un `.ps1` sans BOM est lu en ANSI par
PowerShell 5.1, donc tout accent y est détruit. Écrire ces fichiers en UTF-8
**avec** BOM.

### À faire au prochain build : retirer deux clés orphelines d'Info.plist

`ios/Runner/Info.plist` déclare `NSLocationWhenInUseUsageDescription` et
`NSLocationAlwaysAndWhenInUseUsageDescription`, alors que l'application
n'utilise la position nulle part. Mesuré le 16 octobre : aucun paquet de
géolocalisation dans `pubspec.yaml`, et aucune occurrence de `latitude`,
`longitude`, `GeoPoint` ou `gps` dans `lib/` ni dans `functions/src/`.

Décidé le 16 octobre de soumettre sans corriger : une clé déclarée mais
inutilisée n'est pas un motif de rejet, Apple sanctionne l'inverse. Retirer
les clés aurait imposé un build `53`, donc un numéro de plus et une
désynchronisation d'avec Android, déjà en revue en `1.0.7+52`.

Attention à la confusion de vocabulaire, qui a failli produire une
déclaration fausse dans les deux consoles. « Position » désigne deux choses
différentes ici :

| Ce que porte le modèle | Nature | Origine |
| --- | --- | --- |
| `positions` / `positionCodes` | le **poste de jeu** : Gardien, Défenseur central, Latéral gauche | saisi par le joueur |
| `country`, `city`, `region` | ville et pays déclarés | saisis au clavier |
| `lieu` d'une offre ou d'un évènement | texte libre, « Bamako » | saisi par le club |

Aucune de ces données ne vient de l'appareil. Les catégories « Position »
chez Google et « Location » chez Apple désignent la localisation obtenue du
téléphone, donc **ne pas les déclarer**. La fiche Play actuellement en ligne
annonce pourtant collecter la Position : à vérifier et corriger après la
revue, sans urgence, l'erreur allant dans le sens inoffensif d'annoncer plus
que ce qui est pris.

## Le 16 et 17 octobre : iOS monte, et bute sur un seul point

### Android est parti

Les 8 changements ont été envoyés en revue le 16 octobre : release `52
(1.0.7)` en déploiement complet, +177 pays puis le reste du monde, les trois
éléments de fiche refaits, l'audience 13+ et le Data safety. Statut
`In review`. Managed publishing reste OFF, donc l'approbation publiera
directement dans les 179 pays.

### Ce qui est fait côté App Store Connect

| Élément | État |
| --- | --- |
| Captures d'écran | 5, portées de 1170x2532 à **1179x2556** |
| Description, mots-clés, URL de support, copyright | en place, texte identique à Play |
| Version de la fiche | **1.0.7**, alignée sur le binaire |
| Build | **52 attaché** |
| App Review Information | identifiant, mot de passe, contact, notes en anglais |
| Sign-In Required | coché |
| Content Rights | oui, droits détenus via CGU section 5 |
| Catégories | Sports en principale, Social Networking en secondaire |
| Classification d'âge | **13+** dans 171 pays, 16+ dans 2, A16 au Brésil |
| App Privacy | **publié**, 11 types, usages configurés |
| Prix | **0,00 dans tous les pays** |
| Mise en ligne | automatique après approbation, comme sur Play |

### Le seul blocage restant : la capture iPad 13 pouces

`Add for Review` répond encore : « You must upload a screenshot for 13-inch
iPad displays ». La cause est dans le binaire, pas dans la console :
`ios/Runner.xcodeproj/project.pbxproj` porte `TARGETED_DEVICE_FAMILY = "1,2"`
à douze endroits, donc iPhone **et** iPad. Apple exige alors des captures
iPad, et la famille d'appareils ne se modifie pas depuis App Store Connect.

Décision du 17 octobre : **restreindre à l'iPhone**, ce qui impose un build
`53`. Adfoot est pensée pour le téléphone, aucune interface iPad n'a jamais
été vérifiée, et publier un affichage que personne n'a regardé est un motif
de rejet plus sérieux qu'un numéro de build consommé.

Ce que le build 53 doit emporter, dans cet ordre :

1. `TARGETED_DEVICE_FAMILY` de `"1,2"` à `"1"`, aux douze emplacements.
2. Le retrait de `NSLocationWhenInUseUsageDescription` et
   `NSLocationAlwaysAndWhenInUseUsageDescription` d'`Info.plist`, décidé plus
   haut et reporté faute de build.
3. `pubspec.yaml` en `1.0.7+53`.
4. Tests, `flutter analyze`, gates Android et iOS, contrat admin/mobile.
5. Commit et push sur `master` **et** sur la branche de release, pour que le
   défaut de Codemagic reste correct.
6. Build `ios-production` sur Codemagic, branche `master`.
7. Dans App Store Connect : rattacher le 53, vérifier que l'exigence iPad a
   disparu, puis `Add for Review`.

Android restera en `52` et iOS passera en `53`. C'est assumé : les deux
magasins ne partagent pas leurs numéros, et Android est déjà en revue.

### Deux actions qui n'appartiennent qu'au titulaire du compte

Elles bloqueront la soumission quoi que porte la fiche, et je ne peux pas les
faire :

- **Accepter le contrat Apple Developer Program mis à jour.** Bandeau en tête
  de la liste des apps : « the Account Holder must review and accept ».
- **Renseigner le statut de trader pour l'Union européenne**, exigé par le
  Digital Services Act. Vous distribuez dans 179 pays.

### Ce que Codemagic fait, et ne fait pas

Vérifié dans `codemagic.yaml`, bloc `publishing` de `ios-production` :
`submit_to_testflight: true` et **`submit_to_app_store: false`**. Le build
monte sur TestFlight et s'arrête là. Aucun `beta_groups` n'est déclaré, donc
pas de distribution externe ni de Beta App Review.

Il n'y a donc rien à corriger de ce côté, contrairement à ce qui était
craint. Sur iOS il n'existe qu'un seul chemin : un binaire téléversé apparaît
simultanément dans TestFlight **et** dans le sélecteur de build de la fiche
App Store. Ce ne sont pas deux destinations, c'est le même binaire vu de deux
onglets. La preuve a été faite : le build 52, parti « directement sur
TestFlight », est celui qui est attaché à la version de production.

Et c'est l'inverse d'Android, où les pistes sont réellement séparées et où un
versionCode est consommé pour toutes. Cette différence est exactement ce qui
a coûté le `51` côté Play.

### Note de méthode : les formulaires App Privacy

Onze types de données, chacun avec cinq écrans. Trois pièges rencontrés :

- Le premier clic après l'ouverture d'un dialogue ne prend pas, l'animation
  n'étant pas finie. Cliquer, vérifier, recliquer si besoin ; ne jamais
  enchaîner à l'aveugle, un double clic décoche ce qu'il venait de cocher.
- La position du bouton `Next` change selon la hauteur du dialogue, de 419 à
  475 selon les écrans. Relever la position réelle avant chaque clic.
- Les options hautes d'une liste, comme `Analytics`, sortent de la zone
  visible quand le dialogue est déroulé vers le bas. Remonter d'abord.

