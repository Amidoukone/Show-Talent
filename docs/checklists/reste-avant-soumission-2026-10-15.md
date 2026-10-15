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
| Build mobile Android | `1.0.7+51`, AAB signé, contenu prouvé par témoins | construit, non soumis |
| Build mobile iOS | `1.0.7+51` au déclenchement, Codemagic manuel | non |

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
