# Registre des visuels avant publicité et captures de store

Remplir une ligne **par photo, vidéo ou capture** avant sa diffusion. Conserver
les accords signés dans un espace privé ; ce dépôt ne doit contenir ni pièces
d'identité, ni signatures, ni coordonnées personnelles.

| Référence interne du visuel | Joueur / personnes visibles | Âge vérifié | Auteur et droits du photographe | Usages autorisés (app, publicité interne, campagne externe, App Store, Play Store) | Territoires et durée | Club, maillot, logo : accord | Date et preuve de l'accord | Retrait demandé / effectué | Responsable de validation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| À renseigner | À renseigner dans le registre privé | À vérifier | À vérifier | À préciser séparément | À préciser | À vérifier | Référence du document privé | État et date | À renseigner |

## Visuels publiés le 14 octobre 2026 sur adfoot.org

Neuf visuels sont en ligne sur la page d'accueil : la photo de groupe
(`team`), le portrait du n°10 en hero (`hero-player`) et sept portraits
numérotés par maillot (`player-01` gardien, `02`, `05`, `06`, `07`, `08`,
`12`). La page affirme publiquement, sous la galerie, que ces images sont
publiées avec l'accord du joueur et, pour un mineur, de son parent ou tuteur.

**Accord parental confirmé par le responsable du projet le 14 octobre 2026**,
préalablement à la mise en ligne.

Reste à inscrire dans le tableau ci-dessous, à partir des accords conservés
dans l'espace privé : l'identité des personnes visibles, l'âge vérifié, les
droits du photographe, l'étendue des usages autorisés, la date et la référence
de preuve de chaque accord. Tant que ces lignes sont vides, la traçabilité
produit n'est pas faite, même si l'accord lui-même existe. Les visuels portent
une empreinte de contenu dans leur nom (`player-05.969f9661.jpg`), qui sert de
référence interne stable pour les désigner ici.

## Contrôle avant export

1. Confirmer que le visuel correspond au football réel représenté : poste,
   club, compétition et statut de vérification ne doivent pas être suggérés à
   tort par la légende ou la mise en scène.
2. Vérifier les accords du joueur, des autres personnes identifiables, du
   photographe et, si nécessaire, du club et des marques visibles. Une simple
   autorisation de publier un profil dans l'application ne couvre pas
   automatiquement une campagne publicitaire ou une capture de store.
3. Écarter tout visuel d'une personne mineure tant que le traitement et les
   autorisations adaptés n'ont pas été établis et examinés.
4. Pour les captures de store, privilégier des comptes de démonstration et
   masquer toute conversation, adresse, numéro ou donnée réelle sans accord.
5. Vérifier que la politique de confidentialité publiée et les déclarations
   App Privacy / Data safety correspondent exactement aux SDK et aux usages
   publicitaires de la version soumise.
6. Archiver la référence du visuel exporté, la version de l'application et la
   date de mise en ligne pour pouvoir retirer une campagne ou remplacer une
   capture rapidement.

Cette grille est une traçabilité produit. La validation des droits et du texte
contractuel doit être faite par le responsable légal du projet.

## Captures de la fiche Play, posées le 16 octobre 2026

Cinq captures remplacent les quatre du 23 juillet, qui montraient une
navigation que l'application ne porte plus : elles affichaient Accueil,
Offres, Events, Chat, Outils, alors que le build 52 porte Accueil, Carrière,
Publier, Chat, Profil (`lib/l10n/app_fr.arb:158`). Le bouton Publier, action
principale de création, n'apparaissait sur aucune d'elles.

| Fichier | Écran | État |
| --- | --- | --- |
| `01-video.jpeg` | Fil vidéo, match réel | personnes mineures identifiables, voir ci-dessous |
| `02-profil.png` | Profil joueur | retouchée, adresse remplacée |
| `03-offres.png` | Carrière, onglet Offres | retouchée, critère d'origine retiré |
| `04-evenements.jpeg` | Carrière, onglet Événements | brute |
| `05-messages.jpeg` | Conversations, état vide | brute |

Sources dans `artifacts/store/android/`, jeu final dans `final/`.

### Les deux retouches, et pourquoi elles ne sont pas cosmétiques

**`02-profil`** affichait `amidoudev@gmail.com`, en clair et au centre de
l'écran. C'est l'adresse du compte de revue, celle qui figure dans Sign-in
details et que nous remettons aux relecteurs Google et Apple. La publier dans
179 pays revenait à l'exposer au spam et aux tentatives de reprise sur
précisément le compte dont dépend la revue. Remplacée par
`kanoute@adfoot.org`, tracée en Roboto depuis le cache du SDK Flutter, la
police que l'application utilise elle-même, après mesure de la hauteur d'x
(22 px) et de la couleur d'encre (`#9BA3B0`). C'est le point 4 de la grille
ci-dessus, appliqué.

**`03-offres`** portait « Nous recherchons un milieu offensif **africain** âgé
de 18 ans ». Un critère d'origine dans une annonce de recrutement, affiché
dans 179 pays dont toute l'Union européenne. Le mot a été retiré en déplaçant
les glyphes existants de « âgé de 18 ans. » vers la gauche, puis en comblant
avec du fond prélevé sur la même ligne : aucun caractère redessiné, donc
aucune dérive typographique. Ce n'est d'ailleurs pas ce que fait la recherche,
qui filtre par nationalité, année de naissance et disponibilité
(`talentSearchNationalityLabel`, `talentSearchBornBetweenLabel`,
`talentSearchOpenOnlyLabel`). C'était du texte libre saisi par un club de
test.

Outils conservés pour pouvoir refaire ou vérifier : `scripts/png_pixels.py`,
`scripts/crop-region.ps1`, `scripts/render-text.ps1`,
`scripts/make-feature-graphic.ps1`.

### L'accord parental sur `01-video`

La capture montre des joueurs mineurs identifiables, visages nets, la vidéo
étant étiquetée `#U17`. Le point 3 de la grille ci-dessus impose de l'écarter
tant que les autorisations ne sont pas établies.

**Le 16 octobre 2026, le responsable du projet a confirmé que l'accord
parental conservé couvre cette diffusion**, c'est-à-dire une publication
mondiale sur une fiche d'application, et non la seule mise en ligne sur le
site. La capture a été publiée sur cette base.

Le tableau de traçabilité reste à remplir depuis les accords conservés en
privé : personnes visibles, âge vérifié, droits du photographe, étendue des
usages, date et référence de preuve. Cette confirmation tient lieu de décision
de publier, pas de preuve.

### Le visuel de couverture

Refait le 16 octobre. L'ancien, du 23 juillet, s'adressait aux « coachs ».
Aucun rôle `coach` n'est provisionnable : `allRoles` vaut joueur, fan, club,
recruteur, agent (`lib/utils/account_role_policy.dart`). Le libellé
`profileRoleCoach` qui subsiste dans le code est de l'affichage hérité. Le
nouveau visuel est généré par `scripts/make-feature-graphic.ps1` à partir de
`assets/logo.png` et de la palette réelle (`lib/theme/ad_colors.dart`), donc
regénérable si la marque bouge.

## Captures de la fiche App Store, posées le 16 octobre 2026

Cinq captures prises sur un iPhone 12 avec le build `1.0.7+52` installé
depuis TestFlight, donc sur les vraies données de production.

| Fichier | Écran | État |
| --- | --- | --- |
| `01-video.png` | Fil vidéo, match réel | personnes mineures identifiables |
| `02-profil.png` | Profil joueur | retouchée, adresse remplacée |
| `03-offres.png` | Carrière, onglet Offres | brute |
| `04-evenements.png` | Carrière, onglet Événements | brute |
| `05-video-moderation.png` | Ajout de vidéo, limites et validation admin | brute |

Sources dans `artifacts/store/ios/`, jeu final dans `final/`.

### Le redimensionnement, et pourquoi il était nécessaire

L'iPhone 12 capture en **1170x2532**. App Store Connect n'accepte, pour la
seule taille obligatoire, que **1179x2556** ou **1206x2622**, celles des
iPhone à Dynamic Island. L'iPhone 12 a une encoche, pas une Dynamic Island :
ses captures ne conviennent donc pas telles quelles.

Les cinq ont été portées en 1179x2556 par `scripts/resize-screenshot.ps1`,
en bicubique haute qualité. La déformation a été mesurée avant d'agir :
rapport source 0,462085 contre 0,461268 pour la cible, soit **0,18 %
d'écart**, invisible à l'œil.

Les captures Android n'étaient pas réutilisables pour deux raisons
indépendantes : elles portent la barre de navigation Android, carré, rond et
triangle, et 1080x2400 ne figure dans aucune liste acceptée par Apple.

### La retouche de `02-profil`

Même motif que pour Android : l'écran affichait `amidoudev@gmail.com`,
l'adresse du compte de revue remise aux relecteurs des deux magasins. La
publier dans 179 pays revenait à l'exposer sur le compte dont dépendent les
deux revues. Remplacée par `kanoute@adfoot.org`, tracée en Roboto depuis le
cache du SDK Flutter, après mesure de la hauteur d'x (23 px) et de l'encre
(`#9AA3AD`). C'est le point 4 de la grille, appliqué.

### Ce que le relecteur Apple verra, et qui a été vérifié

L'offre affichée dans `03-offres` ne porte plus de critère d'origine : elle a
été corrigée dans l'application avant la capture, et s'intitule désormais
« Offre pour Milieu de terrain ». La capture iOS est donc propre à la source,
sans retouche, contrairement à son équivalent Android.

### L'accord parental sur `01-video`

La capture montre les mêmes joueurs mineurs identifiables que la version
Android. La confirmation du 16 octobre, consignée plus haut, couvre une
diffusion mondiale sur une fiche d'application et vaut donc pour les deux
magasins.

