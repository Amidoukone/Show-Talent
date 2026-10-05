# Audit global Adfoot — 2 octobre 2026

## Portée et niveau de confiance

Revue statique du checkout `fbd94bd`, de l’application Flutter, des configurations
iOS/Android, des Functions, des règles Firebase, des documents de release et du
contrat mobile/admin. Aucun code produit n’a été modifié, aucun test n’a été
exécuté et aucun service distant n’a été consulté ou modifié. Les résultats
antérieurs cités ci-dessous sont ceux consignés dans les audits du 25–28
septembre ; ils ne sont pas une preuve de l’état du backend ou des binaires au
2 octobre. La réussite rapportée sur iPhone 12 et dans Play internal testing
est une preuve utile de parcours réels, pas une validation exhaustive de
release, charge ou sécurité.

## Avis de release

**Pas de feu vert global pour une publication générale sur la seule base de ce
checkout.** Les fondations sont solides et les contrôles documentés sont
nombreux. Trois décisions restent bloquantes ou quasi bloquantes : finir la
migration de compatibilité des profils, prouver le comportement des artefacts
signés sur les deux plateformes, et établir les droits/usages des images. La
parité effective du portail admin et du backend doit aussi être constatée au
SHA de release.

## Risques prioritaires

### P0 — Migration de sécurité et compatibilité client encore en cours

Le runbook `docs/checklists/public-profile-rollout-2026-09-28.md` indique que
les projections v3 sont complètes, que les règles transitoires sont en
production, et que la validation sur anciens/nouveaux clients puis la bascule
finale restent à faire. Les anciens clients lisent les profils depuis
`users`; le client actuel utilise `public_profiles`. Une bascule prématurée
des règles finales coupe des fonctions des versions installées. Garder les
règles transitoires conserve temporairement une exposition plus large des
profils. C’est une migration à durée et critères de sortie explicites.

**Avant la release :** relever le SHA des règles/index/Functions réellement
déployés, les compteurs de migration, les versions actives (pas seulement les
téléchargements), les tests des deux générations de client et la décision
datée de retrait de l'ancien accès. Définir les seuils d'arrêt sur erreurs
`permission-denied`, profils absents et fonctions cassées. Le contrat admin
impose une source de vérité backend partagée et un ordre lecteur avant
écrivain : exécuter le contrôle inter-dépôts au SHA candidat et documenter les
écarts avant toute promotion.

**Décision confirmée :** le parent/tuteur signe dans l’application admin avant
le provisionnement. L’admin conserve la signature manuscrite capturée, le nom et
le lien du signataire, le pays ISO, la version et le texte exact accepté, ainsi
que les horodatages de signature et d’enregistrement. Le parcours est prévu pour
le Mali, la Côte d’Ivoire, le Sénégal et s’étend à d’autres pays par code ISO.
Après consentement, la fiche football est réservée aux recruteurs vérifiés,
le contact est médié et les médias demandent un accord séparé. Aucun compte
parent mobile n’est prévu. Cette signature capturée atteste le parcours produit ;
elle ne prétend pas être un certificat de signature qualifiée ni vérifier à elle
seule l’identité du parent.

La projection serveur lit la date privée et limite les profils de moins de
18 ans à une fiche football autorisée explicitement par le provisionnement
admin ; la projection est réévaluée lors des changements de profil. Une date
présente mais invalide est traitée de façon conservatrice. L’accès doit rester
conditionné aux règles déployées et au contrôle recruteur vérifié. Le déploiement
du parcours doit suivre la validation des règles sur émulateur et du backfill
v4 ; aucun changement distant n’est effectué par ce document.
Apple exige le traitement des données de mineurs selon les lois applicables et
ses règles UGC incluent filtrage, signalement, blocage et contact publié ; voir
[App Review Guidelines 1.2 et 5.1.4](https://developer.apple.com/app-store/review/guidelines/uk/).
Google exige, pour les apps dont l’audience comprend des enfants, des déclarations
exactes et une action adulte avant l’échange de données personnelles, ainsi
qu’une gestion adulte des fonctions sociales ; voir [Play Families Policy](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en).
La loi applicable dépend des pays : par exemple, l’article 8 du RGPD fixe 16
ans par défaut pour le consentement au traitement lié à un service de la société
de l’information, avec possibilité pour les États membres de choisir 13–15 ans
([texte officiel EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?qid=1787347134762&uri=CELEX%3A02016R0679-20160504)). Ce repère européen ne suffit pas à décider les marchés africains ou autres.

**Décisions et travaux encore requis :** pays de lancement et seuils d’âge par
pays ; format minimal de preuve et métadonnées conservées par l’admin ; procédure
de retrait et révocation immédiate ; définition de « recruteur vérifié » pour
les règles Firestore ; médiation effective des demandes et messages ; accord
distinct et révocable sur chaque média. Les protections doivent être appliquées
serveur/règles, pas seulement dans l’UI.
### P1 — Images, UGC et déclarations des stores

Le propriétaire précise que les images sont destinées aux visuels promotionnels
de l’application et aux captures des stores, pas à des publicités diffusées dans
l’application. `docs/checklists/player-image-release-register.md` définit une bonne traçabilité,
mais chaque visuel doit être enregistré avant usage : joueur et photographe,
club/maillot/logos si nécessaire, finalité (dans l'app, campagne, stores),
territoires, durée, retrait et preuve conservée hors dépôt. Des captures de
comptes de démonstration réduisent le risque de divulgation. L'absence de SDK
publicitaire dans le manifeste de dépendances n'exclut pas une campagne
promotionnelle avec des personnes réelles ; les déclarations doivent décrire
les traitements et SDK réels. Le dossier `assets/` ne contient actuellement
que le logo et des images de remplacement, sans photos de joueurs à intégrer.

### P1 — Compatibilité du portail admin

Le runbook inter-repo décrit des contrats sensibles aux changements silencieux :
champs de profil, chemins privés, règles, index, validateurs des callables,
custom claims et modèles recopiés dans l’admin. Une divergence peut faire
disparaître une donnée sans erreur visible ou provoquer des refus complets
d’écriture. Aucun contrôle local du dépôt mobile seul ne certifie l’état déployé
du portail.

**Avant chaque promotion :** contrôler les miroirs et les 18 callables,
confirmer les versions du portail et des Functions, les claims des opérateurs,
la région `europe-west1`, les index `READY` et la source effective de chaque
champ partagé. Utiliser le gate cross-repo avec le chemin du dépôt admin prévu
par le runbook.

## Architecture, efficacité et exploitation

- **Fondations positives :** séparation des couches `models/services/controllers`,
  services spécialisés vidéo, dépôts de données, tokens de thème et vocabulaire
  footballistique centralisé ; pagination, projections publiques, file de
  fanout, App Check, règles et garde-fous automatisés existent déjà.
- **Complexité élevée :** 105 fichiers sous `lib/screens`, `lib/controller` et
  `lib/services`; le feed vidéo a une architecture dédiée, tandis que plusieurs
  écrans métier portent encore beaucoup de logique UI. La revue du thème montre
  567 occurrences de styles/couleurs/espacements explicites dans écrans et
  widgets. Ce compte signale un coût de cohérence, pas à lui seul un défaut.
  Migrer par composants partagés et parcours, jamais par refonte globale en une
  release.
- **Recherche :** l’audit du 28 septembre documente une recherche texte vidéo
  limitée aux vidéos récentes lorsque l’index d’auteurs ne trouve rien. Le
  produit doit annoncer une portée cohérente ou mettre en place une indexation
  paginée dédiée avant de promettre une recherche exhaustive.
- **Fanout notifications :** reprise Â« au moins une fois Â» ; une interruption
  entre envoi et curseur peut produire un doublon. Conserver un identifiant de
  campagne idempotent et mesurer les reprises avant d’augmenter le volume.
- **Performance/coûts :** pagination et réduction des préchargements vidéo sont
  positives. Il manque ici des mesures récentes de latence, démarrage à froid,
  mémoire, consommation réseau/batterie et coûts par parcours à charge réaliste.
  Fixer des budgets et comparer Android bas/milieu de gamme et iPhone pris en
  charge, sur réseau faible et reprise après arrière-plan.
- **Erreurs silencieuses :** la recherche statique trouve quelques traitements
  d’erreurs volontairement absorbés (`catch (_) {}` et erreurs avalées sur
  tâches secondaires). Leur présence peut être légitime pour cache/UI ; chaque
  site touchant données métier, navigation, notification ou upload doit avoir
  soit une métrique/log exploitable, soit une justification explicite et un
  comportement de reprise. Ne pas remplacer aveuglément ces traitements.
- **Dépendances et sécurité :** l’audit du 28 septembre rapporte zéro avis Node
  high/critical, avec des avis modérés. Refaire l’inventaire au SHA final et
  examiner les transitive dependencies exploitées. Les contrôles locaux ne
  remplacent pas la revue IAM, des journaux, des secrets Codemagic/Firebase et
  des règles réellement déployées.

## Identité footballistique et qualité visuelle

Une palette sombre et verte, un thème Material 3, des rayons/espacements
centralisés et des composants `Ad*` existent déjà. Le thème est donc une base
utile, mais l’identité sportive dépend surtout de la hiérarchie des données et
de la cohérence d’usage dans chaque écran, pas de décorations football ajoutées
partout.

Direction recommandée :

1. Présenter d’abord les informations de recrutement vérifiables : poste,
   pied, âge/catégorie, club actuel, statistiques avec saison/compétition,
   disponibilité et statut de vérification. Ne jamais suggérer un niveau,
   contrat ou badge officiel non prouvé.
2. Donner aux parcours des objectifs nets : découvrir les talents, évaluer une
   fiche, contacter, gérer les opportunités. Distinguer visuellement joueur,
   club, recruteur et agent sans créer quatre applications différentes.
3. Réserver le vert de marque à l’action et à l’état actif ; garder couleurs
   sémantiques accessibles pour confiance, réussite, alerte et erreur. Vérifier
   contraste, agrandissement texte, zones tactiles, RTL éventuel et petits
   écrans.
4. Unifier cartes de talent, badges, statistiques, filtres, formulaires,
   états vides/erreur/chargement et confirmations avec les composants `Ad*`.
   Introduire les changements écran par écran, avec comparaison visuelle et
   vérification des rôles et langues FR/EN.
5. Employer les images des joueurs comme preuve/contenu éditorial autorisé,
   cadrées pour les interfaces réelles. Préparer une bibliothèque de visuels
   de démonstration sans donnée personnelle pour stores et tests.

## Plan de travail sans rupture

### Porte 0 — état de référence

Figer SHA, version, environnements Firebase, version du portail admin et
artefacts déjà en circulation. Exporter les configurations effectives sans
copier de secret dans le dépôt. Contrôler règles/index/Functions, migration et
versions clientes. Aucun changement de schéma pendant cette collecte.

### Porte 1 — décisions métier et sécurité

Clore l’âge/U17-U19, droits d’images, politique de confidentialité et données
des stores ; fermer la migration de profils selon ses critères ; vérifier les
callables et suppressions avec des parcours adversariaux sur staging. Préparer
rollback backend et seuils d’arrêt.

### Porte 2 — release candidates

Produire AAB et IPA signés avec identifiants figés, inspecter les artefacts,
archiver checksums et rapports. Parcours de bout en bout : Auth/email,
provisionnement admin, profil public/privé, recherche paginée, vidéo/upload,
offre/événement, chat/blocage/signalement, CV et suppression. Exécuter sur
Android réel et TestFlight iOS, avec réseau faible, permissions refusées,
reprise après interruption et comptes adultes de démonstration. Surveiller les
journaux et comparer les versions du backend.

### Porte 3 — amélioration visuelle progressive

Commencer par l’inventaire d’écrans et une spécification de composants
footballistiques (tokens, cartes de talent, badges fiables, statistiques,
états). Choisir un parcours complet à faible couplage, livrer derrière un flag
si nécessaire, vérifier FR/EN et les rôles, puis élargir. Ne pas mélanger cette
évolution avec une migration Firestore ou une modification de règles.

**Première tranche livrée dans le checkout :** la carte de résultat de
recherche des talents utilise maintenant le composant réutilisable
`AdTalentResultCard`. Elle hiérarchise poste, année de naissance, nationalités,
club et niveau, avec libellés de poste/niveau adaptés à FR/EN, photo en
cache/repli, badge de confiance conditionnel et état de disponibilité accessible.
Aucun champ ou comportement de recherche n'a changé. Analyse Flutter et
contrôles ciblés ont réussi le 2 octobre.

### Porte 4 — promotion et observation

Déployer le lecteur avant l’écrivain pour tout contrat admin/mobile. Promouvoir
progressivement, surveiller crashes, permission-denied, authentification,
échecs d’upload, profils absents, fanout, latence et coûts. Arrêter au seuil
prédéfini et revenir au dernier artefact/backend compatibles.

## Limites

Cette revue n’a pas accès aux consoles Apple, Google, Codemagic ou Firebase, aux
logs de production, au binaire signé, au dépôt admin externe ni aux autorisations
des joueurs. Elle ne mesure ni charge ni comportement visuel réel. Les éléments
de ces domaines sont des preuves à obtenir avant le feu vert, pas des défauts
affirmés du service actuellement en ligne.
