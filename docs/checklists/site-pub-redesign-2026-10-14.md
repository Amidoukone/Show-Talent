# Refonte du site public adfoot.org, 14 octobre 2026

Le site promettait « Rejoindre maintenant » vers une application où l'inscription
n'existe pas, portait un logo abandonné et un formulaire de contact qui n'envoyait
rien. Ce relevé décrit ce qui a été mesuré, ce qui a été refait, et ce qui reste à
faire avant de déployer.

Aucun déploiement n'a été fait. `lib/`, `functions/src/`, `firestore.rules` et les
pages fonctionnelles du site ne sont pas touchés.

## Le défaut de fond : le site promettait ce que le produit ne fait pas

C'est ce qui explique les demandes quotidiennes de joueurs et de parents. Le site
envoyait les visiteurs vers une porte fermée.

| Ce que disait le site | Ce que fait le produit |
| --- | --- |
| « Rejoindre maintenant » → téléchargement de l'app | `publicSelfSignupRoles` (`lib/utils/account_role_policy.dart`) est la **liste vide**. `signup_screen.dart` est un écran d'information sans formulaire. Un joueur qui installe l'app n'atteint rien. |
| « formation, accompagnement et coaching professionnels », « préparation physique, coaching vidéo » | Les CGU publiées le même jour disent l'inverse : « Adfoot ne promet ni détection, ni essai, ni sélection, ni contrat, ni transfert » et « n'agit pas comme agent ou représentant du joueur ». |
| « Messagerie instantanée … sans intermédiaire » | Pour un joueur de moins de 18 ans, la messagerie directe est désactivée et les demandes de contact sont médiées par Adfoot. |
| Rien sur l'âge minimum, rien pour les parents | L'âge minimum est 12 ans et tout joueur mineur exige un accord parental enregistré. Les parents écrivent tous les jours. |
| Formulaire `<form action="mailto:…" method="post">` | Les navigateurs modernes ignorent un POST vers `mailto:`. Le visiteur cliquait « Envoyer » et **rien ne partait**. |

Le parcours réel est déjà écrit dans l'application
(`signupUserJourneyCardMessage`, `lib/l10n/app_fr.arb`) : « 1. Contacter
l'administration Adfoot. 2. Recevoir le lien… ». Le site devait être cette étape 1
et ne l'était pas. Il l'est maintenant.

## Ce qui a été refait

Structure et palette reprises du mockup validé le 10 septembre 2026 (thème sombre
`#0E1114`, vert de marque `#2ED573`, Space Grotesk + Work Sans). **La copie du
mockup n'a pas été reprise telle quelle** : elle datait d'avant ces constats et
contenait « Créer mon profil joueur » et « sans intermédiaire », c'est-à-dire les
deux promesses fausses ci-dessus.

Plan de la page : voir « Ordre des sections après relecture » plus bas, qui fait
foi. Deux sections y sont nouvelles et répondent directement au public observé.

Deux sections sont nouvelles et répondent directement au public observé :

- **Parents & tuteurs.** Âge minimum 12 ans, accord parental enregistré par
  l'équipe, profil masqué tant qu'il n'est pas donné, fiche limitée aux
  recruteurs vérifiés, contact médié, retrait possible à tout moment par
  `support@adfoot.org` sans compte Adfoot.
- **« Adfoot ne vous demande jamais d'argent. »** Les jeunes joueurs africains
  sont une cible connue des faux agents. Le site dit noir sur blanc qu'Adfoot est
  gratuit pour les joueurs, ne promet ni essai ni contrat, n'est l'agent de
  personne et ne prend aucune commission, ce qui est exactement ce que disent
  les CGU, §7.

Bilingue FR/EN : le français est écrit dans le HTML et reste entièrement lisible
sans JavaScript ; l'anglais vit dans des attributs `data-en*` appliqués par un
script de 60 lignes. Le choix est mémorisé, et les liens légaux basculent vers
les versions anglaises publiées le même jour.

Prise de contact : WhatsApp `+223 70 45 33 45` en principal, le canal que
l'application utilise déjà (`lib/utils/adfoot_support.dart`), avec message
pré-rempli, plus un formulaire qui compose un e-mail vers `support@adfoot.org`
au lieu d'un POST ignoré.

## Révision de la copie après relecture

Deux retours à la première relecture : les textes étaient trop génériques, et
le tiret cadratin devait disparaître. Les deux allaient ensemble, parce que
le caractère servait surtout une formule répétée six fois sur la page
(« X, pas Y »), qui tenait lieu d'argument.

Voix retenue pour le titre : le niveau se montre, il ne se raconte pas. La
copie a ensuite été reprise dans ce registre, chaque phrase appuyée sur un fait
vérifiable du produit plutôt que sur une abstraction.

| Avant | Après |
| --- | --- |
| « Le talent africain mérite d'être vu par les bonnes personnes. » | « Le niveau d'un joueur se montre. Il ne se raconte pas au téléphone. » |
| « Que vous cherchiez à être repéré ou à repérer, tout le monde passe par la même porte. » | « Cinq rôles existent dans l'application. Les cinq passent par la même porte : notre équipe ouvre le compte une fois qu'elle a vérifié qui vous êtes. » |
| « Recherchez par poste, catégorie d'âge et niveau de club, pas par mots-clés approximatifs. » | « Cherchez un gardien U17 ou un défenseur central, et obtenez exactement cela. » |
| « Concrètement, ce qui permet aux bonnes personnes de se trouver. » | « Ce que vous utilisez vraiment une fois le compte ouvert. » |
| « Des joueurs réels, un vrai terrain, de vrais postes. » | « Les photos de cette page sont celles des joueurs que nous suivons, prises sur leur terrain. Leur fiche porte les mêmes postes que ceux qu'ils occupent le samedi. » |

**Tirets supprimés : 58 sur l'ensemble du site**, dont 34 sur la page d'accueil,
24 sur les pages légales et la 404, et cinq dans des commentaires de
`auth-action.js`, `robots.txt`, `sitemap.xml` et `styles.css`. Chaque occurrence
a été relue et la phrase reformulée, jamais le caractère simplement échangé. Les
tirets demi-cadratins ont suivi : le pied de page dit `2025-2026`.

`auth-action.js` est un fichier fonctionnel : les trois occurrences y étaient
dans un commentaire, et `git diff --numstat` confirme **3 lignes modifiées**,
aucune ligne de code. La règle est consignée pour les prochaines rédactions.

## Ordre des sections après relecture

« Les joueurs que nous accompagnons » est remontée avant « Ce que fait
l'application », à la demande de la relecture. Le plan est désormais :

1. Hero
2. À qui s'adresse Adfoot
3. Comment on entre, concrètement
4. **Les joueurs que nous accompagnons**
5. Ce que fait l'application
6. Votre enfant joue, c'est vous qui décidez
7. Adfoot ne vous demande jamais d'argent
8. Parlez-nous du joueur
9. Demander un accès

Le récit y gagne : on explique comment entrer, on montre les joueurs réels, puis
on détaille l'outil.

Deux conséquences traitées, parce qu'un simple déplacement les aurait laissées
visibles :

- **Trois cartes retirées.** La section déplacée portait « Poste et catégorie
  d'âge », « Vu en jeu, pas seulement décrit » et « Les bonnes personnes,
  directement », qui répètent mot pour mot « Recherche structurée », « Profils
  vidéo & CV » et « Profils vérifiés » de la section désormais collée juste
  après. La section garde son titre, la photo de groupe, la galerie et sa
  mention de droits à l'image : elle sert de preuve visuelle, et l'explication
  du mécanisme reste dans la section suivante, à sa place.
- **Alternance des fonds rétablie.** Deux sections `section-alt` se seraient
  suivies. Les classes ont été réattribuées : clair et sombre alternent sur
  toute la page, du hero au contact.

La section Parents montre maintenant le joueur n°5 au lieu du gardien, et les
textes alternatifs de la galerie nomment chacun son numéro de maillot plutôt que
de répéter sept fois la même phrase.

## Images : 22 Mo → 1,4 Mo

Les neuf visuels fournis étaient des PNG de 2,3 à 2,7 Mo, soit **22 Mo** pour un
public majoritairement sur données mobiles. Un doublon exact a été écarté
(`Determined Number 8 Soccer Portrait (1).png`, même MD5 que l'original).

| Fichier | Dimensions | Poids |
| --- | --- | --- |
| `hero-player.jpg` | 820 × 1457 | 231 Ko |
| `team.jpg` | 1400 × 933 | 292 Ko |
| sept portraits `player-NN.jpg` | 640 × 960 | ~130 Ko chacun |

**Les portraits sont nommés d'après le numéro de maillot**, et c'est une
correction. Le premier jeu portait des numéros de séquence : `player-05.jpg`
montrait le joueur n°12 et `player-01.jpg` le n°5, ce qui rendait toute demande
du type « remplace le joueur numéro 5 » ambiguë. Correspondance avec les
sources de `media-source/marketing-2026-10/` :

| Publié | Maillot | Source |
| --- | --- | --- |
| `player-01.jpg` | 1, gardien | `Confident Goalkeeper on the Turf.png` |
| `player-02.jpg` | 2 | `Confident Soccer Player on Turf.png` |
| `player-05.jpg` | 5 | `Confident Blue Soccer Portrait.png` |
| `player-06.jpg` | 6 | `Focused Footballer on the Turf.png` |
| `player-07.jpg` | 7 | `Confident Young Soccer Player on Turf.png` |
| `player-08.jpg` | 8 | `Determined Number 8 Soccer Portrait.png` |
| `player-12.jpg` | 12 | `Focused ADFOOT Soccer Portrait.png` |
| `hero-player.jpg` | 10 | `Joueur Pub.png` |
| `team.jpg` | groupe | `A_DFOOT Team Poster Montage.png` |

Chaque image est utilisée exactement une fois sur la page : le n°10 en hero, le
n°5 dans la section Parents, les six autres portraits en galerie, et la photo de
groupe en ouverture de « Les joueurs que nous accompagnons ».

### Le nom porte un condensé du contenu

`firebase.json` sert `/images/**` en `public, max-age=31536000, immutable`.
Réutiliser un nom de fichier pour un contenu différent condamne donc tout
visiteur déjà venu à voir l'ancienne image **pendant un an**, sans aucun moyen de
pousser une correction.

Ce n'est pas théorique : le renommage par numéro de maillot a fait porter
`player-05.jpg` successivement au joueur n°12 puis au n°5. En relecture locale,
le navigateur a continué d'afficher le n°12 dans la section Parents alors que le
serveur envoyait bien le n°5, somme de contrôle à l'appui. Le site n'était pas
déployé, donc aucun visiteur n'a été touché.

Les images portent désormais huit caractères de leur empreinte SHA-256, par
exemple `player-05.969f9661.jpg` : une image modifiée change forcément d'URL, et
`immutable` redevient une promesse exacte.

Le garde-fou `test/video_release_quality_guardrails_test.dart` refuse une image
référencée sans condensé, et recalcule l'empreinte de chaque fichier pour
vérifier qu'elle correspond toujours à son nom. Vérifié en négatif : en
remplaçant le contenu de `player-05.969f9661.jpg` par une autre photo, le test
échoue avec « no longer matches its own content hash ».

Après avoir ajouté ou remplacé une image, renommer et mettre à jour les
références en une commande :

```powershell
npm.cmd run site:images:hash     # renomme et corrige index.html
npm.cmd run site:images:check    # verifie sans rien ecrire, sort en code 1 si besoin
```

`scripts/hash-site-images.mjs` est idempotent : une image déjà condensée et
toujours exacte est laissée telle quelle. Il signale aussi une image publiée que
la page n'utilise pas, et une référence morte.

Total servi : **1,4 Mo**, dont 283 Ko seulement au-dessus de la ligne de
flottaison : les huit autres images sont en `loading="lazy"`.

Les PNG d'origine ne sont **pas supprimés** : ils n'étaient suivis par aucun
commit et n'existaient que sur ce disque. Ils sont déplacés dans
`media-source/marketing-2026-10/`, hors de `site_pub/` donc hors déploiement, et
`media-source/` est ajouté à `.gitignore` pour ne pas charger le dépôt de 22 Mo.
Les quatre anciennes images (`hero.jpg`, `about.jpg`, `feature1.jpg`,
`feature2.jpg`) sont retirées.

## Logo : le site portait encore l'ancienne marque

Mesuré, pas supposé : toutes les déclinaisons du site affichaient **« AD.FOOT »**
en vert foncé, avec une silhouette de joueur bondissant, alors qu'Android et iOS
expédient **« ADFOOT »** en noir avec le joueur frappant le ballon et les deux
arcs (`android/app/src/main/res/mipmap-*/ic_launcher.png`).

Toutes les icônes sont régénérées depuis `assets/logo.png`, la source officielle
de l'application, par détection du cadre du contenu (x 48→1192, y 102→1104) puis
recentrage sur un carré avec 8 % de marge, la même composition que le lanceur
Android :

`favicon.ico` (16/32/48 en PNG embarqué), `favicon.png` 64, `favicon-96x96.png`,
`apple-touch-icon.png` 180, `web-app-manifest-192x192.png`,
`web-app-manifest-512x512.png`.

`favicon.svg` portait l'ancienne marque et ne peut pas être régénéré depuis un
raster : il est supprimé, avec son lien dans `404.html` et sa règle d'en-tête
devenue morte dans `firebase.json`. PNG + ICO couvrent tous les navigateurs.

L'image de partage `icons/og-image.png` (ancien logo, format 2214 × 2411 inutilisable
par les réseaux sociaux) est remplacée par `icons/og-image.jpg` au format 1200 × 630
attendu : la photo de groupe, logo ADFOOT et baseline compris, sur bandes
anthracite.

`theme-color` était déclaré en vert dans trois fichiers et en anthracite dans un
quatrième. Les quatre disent maintenant `#0E1114`, la couleur de surface de
toutes les pages du site.

## Vérifications passées

- `flutter test` : **1041/1041**.
- `npm.cmd run release:android:check` (gate complet) : vert.
- Les 22 ressources référencées par la page d'accueil répondent **200** sur un
  serveur local ; aucune image présente sur le disque n'est inutilisée ; balises
  structurantes appariées ; 107 chaînes traduites, aucune vide.
- Aucune référence résiduelle à un fichier supprimé dans le site.
- **Pages fonctionnelles intactes**, vérifié par `git status` : `verify/`,
  `reset/`, `auth-action.js`, `auth-action.css`, `.well-known/`. Seule la
  couleur de thème de `download/android/index.html` change.

Un garde-fou a dû être corrigé : `video_release_quality_guardrails_test.dart`
exigeait littéralement `src="/images/hero.jpg"`. Il épinglait un nom de fichier
qu'une refonte a le droit de changer. Il vérifie désormais que le bloc hero porte
bien une image, et le test voisin continue de vérifier que chaque image
référencée existe réellement : c'est ce dernier qui protège contre une vraie
régression.

## Reste à faire avant de déployer

1. **Remplir le registre des visuels** :
   `docs/checklists/player-image-release-register.md` est encore à l'état
   « À renseigner », et son point 3 demande d'« écarter tout visuel d'une
   personne mineure tant que le traitement et les autorisations adaptés n'ont pas
   été établis ». Les neuf photos montrent des joueurs identifiables et
   visiblement mineurs, et les CGU publiées exigent pour eux une autorisation
   promotionnelle **distincte**, donnée par le parent ou tuteur et consignée
   séparément. La page elle-même l'affirme publiquement sous la galerie : « Leurs
   images sont publiées avec l'accord du joueur et, pour un mineur, de son parent
   ou tuteur. » Cette phrase doit être vraie avant la mise en ligne.
2. **Relire la page sur un téléphone réel**, en français et en anglais, en
   vérifiant la bascule de langue, le bouton WhatsApp (message pré-rempli) et le
   formulaire (il doit ouvrir l'application e-mail).
3. **Déployer** puis contrôler :

   ```powershell
   npm.cmd run hosting:marketing:deploy:production
   node scripts/check-production-hosting.mjs
   ```

   Le contrôle compare désormais 15 fichiers octet à octet, dont `styles.css`,
   `manifest.json`, `favicon.ico`, `apple-touch-icon.png` et les six pages
   légales.

Point mineur hors périmètre, relevé au passage : `web/index.html`, le gabarit de
build Flutter Web, référence `icons/og-image.png` qui n'existe pas dans `web/icons/`.
Cette surface n'est pas déployée sur adfoot.org.
