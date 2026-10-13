# Messagerie, notifications iOS et réseau lent — 10 octobre 2026

Trois défauts constatés sur le build 44 en test, corrigés ici. Le premier est
une panne totale, pas une dégradation : **aucun message ne pouvait plus être
envoyé depuis l'application**.

## 1. « Impossible de démarrer la conversation » — lecture d'un document absent

### Ce qui se passait

`BlockRepository.isBlockedEitherWay` lit les deux identifiants directionnels de
blocage (`{A}_{B}` et `{B}_{A}`) avant **chaque** ouverture de conversation et
**chaque** envoi. Dans la quasi-totalité des cas, aucun des deux documents
n'existe : personne n'a bloqué personne.

Or Firestore évalue bien la règle d'un `get` sur un document inexistant, mais
`resource` y est `null`. La règle `blocks` lisait `resource.data.blockerUid` :
elle ne pouvait donc pas répondre « pas de blocage », elle **refusait** la
lecture. Le client recevait `permission-denied` sur le chemin normal.

Pire, dans `ChatController`, la pré-vérification était placée **avant** le
`try`. L'exception remontait brute jusqu'à l'écran, dont le `catch` générique
affichait « Impossible de démarrer la conversation » — un message qui ne nommait
rien. Dans `sendMessage`, la même erreur était interprétée comme une session
perdue : l'utilisateur lisait « Votre session a été fermée ».

### Pourquoi la suite de tests est restée verte

Les 97 tests émulateur couvraient la lecture d'un blocage **existant** dans les
deux sens, et le refus pour un tiers. Aucun ne lisait un blocage **inexistant** —
c'est-à-dire le cas de production. La fonctionnalité de blocage, elle, marchait :
créer un blocage et lister les siens passent par des requêtes, où `resource`
n'est jamais nul.

### Correction, en deux couches indépendantes

| Couche | Fichier | Effet |
| --- | --- | --- |
| Règles | `firestore.rules` | `blocks` scinde `read` en `get`/`list`. Le cas absent est autorisé par l'**id**, qui encode déjà la paire : on ne peut interroger qu'un blocage qui vous nomme. Le contenu reste la source d'autorité dès que le document existe, et les requêtes gardent la vérification par contenu. |
| Client | `block_repository.dart` | La pré-vérification devient consultative : une lecture sans réponse vaut « rien de connu contre », pas « envoi impossible ». La règle d'écriture (`isBlockedPair`) tranche de toute façon côté serveur. |
| Client | `chat_controller.dart` | Les trois pré-vérifications passent dans le `try`, avec `on ChatFlowException { rethrow; }` pour ne pas ré-étiqueter un message déjà lisible. |

Les deux couches sont volontairement indépendantes : **un build publié peut
tourner devant des règles plus anciennes** (voir
`docs/inter-repo-admin-mobile-runbook.md`, ordre de déploiement). Le correctif
client suffit à rétablir l'envoi même si les règles ne sont pas encore
déployées.

### Même classe de défaut, ailleurs

La même correction est appliquée partout où le client lit par id un document
qui peut légitimement ne pas exister, et où le code traite déjà
« introuvable » comme un résultat normal :

- `conversations` — conversation supprimée par l'autre participant
  (`watchConversationById`, `fetchConversationData`)
- `public_profiles` — projection absente ou retirée
  (`canSendMessage`, `watchUserById`)
- `contact_intakes` — demande supprimée par un admin
  (`_recoverMissingGuidedContactIntake`)
- `videos` — vidéo supprimée dont un lien de partage ou une notification
  porte encore l'id (`fetchReadyVideoById`)

Dans tous les cas le garde n'ouvre que l'absence : aucune condition de contenu
n'est relâchée, et les requêtes (`list`) conservent la vérification complète.

### Preuve, pas seulement raisonnement

Le moteur de règles confirme le diagnostic. La suite émulateur exécutée contre
les règles **d'avant** le correctif échoue sur exactement six cas — dont la
lecture d'un blocage inexistant — et les mêmes passent après :

```
--- contre les règles d'avant ---
ECHEC  [autorise]  je demande si un blocage me concernant existe (il n'existe pas)
ECHEC  [autorise]  je demande dans l'autre sens (il n'existe pas non plus)
ECHEC  [autorise]  lire une conversation supprimee repond introuvable
ECHEC  [autorise]  lire une projection publique absente repond introuvable
ECHEC  [autorise]  lire une video supprimee repond introuvable
ECHEC  [autorise]  lire une demande de contact supprimee repond introuvable
107/113 conformes

--- après correctif ---
113/113 conformes
```

L'état de production le confirme de l'autre côté. Au 10 octobre, avant
déploiement : **`blocks` contient 0 document** — donc *chaque* appel de
`isBlockedEitherWay` lisait deux documents inexistants et était refusé, soit
100 % des tentatives — et **`conversations` contient 0 document**, aucune
conversation n'ayant jamais pu être créée. Les quatre comptes portent bien
`isMinorProfile: false` et leurs quatre projections publiques existent : le
reste de la chaîne était sain.

Déployé en production le 10 octobre à 17:39 UTC ; `check-backend-parity.ps1`
confirme l'empreinte distante identique au dépôt et 44/44 index `READY`.

### Tests ajoutés

- `test/rules/firestore-rules.test.mjs` — lecture d'un blocage inexistant
  (autorisée quand il vous nomme, refusée sinon), les deux flux directionnels,
  et les quatre lectures par id ci-dessus. Exécutés : voir « Faire tourner
  l'émulateur de règles » plus bas pour la seule chose qui manquait.
- `test/firestore_rules_missing_document_guardrails_test.dart` — mêmes
  invariants assertés sur le **texte** des règles, donc exécutables dans
  `flutter test` sans émulateur.
- `test/chat_repository_test.dart` — le garde-fou qui interdisait toute lecture
  directe de la conversation est remplacé par celui qui compte désormais : la
  lecture directe doit rester une optimisation repliable.

## 2. Notifications iOS — deux pannes superposées

`WebMessagingHelper.getTokenWithRetry` appelait `getToken()` sur mobile sans
attendre le jeton APNs. Sur iOS, `getToken()` lève
`[firebase_messaging/apns-token-not-set]` tant que le système n'a pas livré ce
jeton — et il arrive de façon **asynchrone**, après l'accord de l'utilisateur,
jamais à l'instant où `requestPermission()` rend la main. L'exception était
attrapée et `null` retourné **sans un seul réessai** : la boucle de réessai ne
servait que le Web.

Conséquence : aucun jeton enregistré sur iOS, le backend répondait
`token_missing` à chaque envoi, et personne ne recevait de notification — ni un
message, ni la validation de sa propre vidéo. Rien ne le signalait : l'écran
venait d'annoncer à l'utilisateur que les notifications étaient activées.

Corrections :

- `web_messaging_helper.dart` — attente bornée du jeton APNs (12 s, par
  sondages) avant `getToken()`, puis réessais de `getToken()` (utiles aussi sur
  Android, où l'enregistrement FCM passe par le réseau).
- `auth_controller.dart` — la permission est demandée **avant** la lecture du
  jeton, et non après : l'ordre précédent garantissait un aller-retour perdu à
  chaque connexion. Les deux étapes ne bloquent plus la connexion
  (`unawaited`), sinon l'attente APNs s'ajouterait au temps de connexion.
- `notifications.dart` — `initLocal()` initialise enfin iOS/macOS
  (`DarwinInitializationSettings`), sans redemander les permissions : sans
  cela, un appui sur une notification affichée localement n'atteignait pas le
  routeur et la destination encodée dans le payload était perdue.
- `admin_content_actions.ts` — le texte des notifications de modération était
  non accentué (« Video approuvee »). `normalizeNotificationText` ne corrige
  que le mojibake, pas les accents manquants.

### Confirmé par l'état de production

Le compte de test iOS (rôle `joueur`, créé le 10 octobre à 12:32 UTC,
`sNwqlaBBWaTg9S1DZWJOuoXXURX2`) n'a **aucun** document `user_push_tokens` ni
champ `fcmToken` hérité. Les deux seuls jetons enregistrés dans le projet
appartiennent à des appareils **Android** (comptes `recruteur` et `club`, mis à
jour les 9 et 10 octobre). L'iPhone n'a donc jamais obtenu de jeton — ce qui est
exactement le défaut décrit ci-dessus, et non un problème de livraison.

Corollaire : la clé APNs **ne peut pas encore être testée par un envoi**. FCM ne
répond `THIRD_PARTY_AUTH_ERROR` qu'en routant vers un jeton iOS, et il n'en
existe aucun. Un envoi à blanc (`validate_only`) est accepté pour les deux
jetons Android, mais il ne contacte pas APNs : cela ne prouve rien sur iOS.

### Deuxième blocage iOS, indépendant : aucune clé APNs

Vérifié dans Firebase Console le 10 octobre pour `adfoot-production`, app
`ADFOOT-Production-iOS` / `org.adfoot.app` :

```
APNs Authentication Key   -> No development APNs auth key
                             No production APNs auth key
APNs Certificates         -> No development APNs certificate
                             No production APNs certificate
```

FCM n'a donc **aucun moyen de s'authentifier auprès d'Apple** pour ce bundle.
C'est une panne distincte de la précédente et elle ne se corrige pas dans ce
dépôt : même avec le correctif client, un jeton obtenu n'aurait rien reçu. Les
deux se masquaient mutuellement — sans jeton, un envoi répond `token_missing` et
n'atteint jamais APNs ; sans clé APNs, FCM répond `THIRD_PARTY_AUTH_ERROR`,
mais seulement une fois qu'il a un jeton à router.

#### Ce n'est pas la clé API App Store Connect

Piège rencontré le 10 octobre. Apple délivre deux sortes de fichiers `.p8`, créés
à deux endroits différents, et les deux se téléchargent sous le nom
`AuthKey_XXXXXXXXXX.p8` — le nom du fichier ne les distingue pas.

| | Clé API App Store Connect | Clé d'authentification APNs |
| --- | --- | --- |
| Sert à | envoyer les builds (Codemagic) | envoyer les notifications |
| Créée dans | App Store Connect -> Users and Access -> Integrations | Apple Developer -> Certificates, Identifiers & Profiles -> Keys |
| Livrée avec | Key ID + **Issuer ID** (UUID) | Key ID + **Team ID** (10 caractères) |
| Acceptée par Firebase | non | oui |

Le signe fiable est l'**Issuer ID** : s'il y en a un, c'est la clé App Store
Connect, celle que `IOS_CODEMAGIC_SETUP_RUNBOOK.md` fait créer à sa section 3
pour l'intégration `adfoot_app_store_connect`. Elle n'a rien à voir avec APNs et
Firebase la refuse.

À faire une fois, par le propriétaire du compte Apple :

1. <https://developer.apple.com/account/resources/authkeys/list> -> **+** ->
   cocher **Apple Push Notifications service (APNs)** -> *Continue* ->
   *Register*. Noter le **Key ID** affiché ; le **Team ID** se lit sur
   <https://developer.apple.com/account> (encart *Membership details*), et ce
   n'est **pas** l'Issuer ID.
   Si la liste contient déjà une clé dont les services incluent APNs et que le
   `.p8` a été conservé, la réutiliser : rien à créer. S'il a été perdu, il faut
   révoquer et recréer — Apple ne le repropose jamais.

   **Écran *Configure Key*, deux choix définitifs.** Apple prévient que
   « the APNs configuration for accessible environment and key restriction type
   can't be changed once saved », et le défaut proposé est le mauvais :

   - **Environment : `Sandbox & Production`**, jamais `Sandbox` seul. `Sandbox`
     ne couvre que les builds lancés depuis Xcode avec un profil de
     développement. TestFlight et l'App Store utilisent l'environnement APNs
     *production*, et les deux workflows de `codemagic.yaml` signent déjà en
     `aps-environment: production` — staging compris, puisque
     `verify-ios-ipa.sh "$BUNDLE_ID" production` fait échouer le build sinon.
     Une clé Sandbox ne servirait donc à aucun build publié de ce projet.
   - **Key Restriction : `Team Scoped (All Topics)`**, le défaut, à garder. Avec
     `Topic Specific` il faudrait énumérer les topics sans pouvoir y revenir, et
     il en faut deux : `org.adfoot.app` et `org.adfoot.app.staging`. Le périmètre
     équipe couvre les deux, donc une seule clé sert les deux projets Firebase.
2. Télécharger le fichier `.p8`. **Apple ne le propose qu'une seule fois** —
   le reperdre impose de révoquer la clé et d'en créer une autre. Ne jamais le
   committer : il ouvre l'envoi de notifications à toutes les apps du compte.
3. Firebase Console -> `adfoot-production` -> Paramètres du projet ->
   **Cloud Messaging** -> *Apple app configuration* -> **APNs Authentication
   Key** -> *Upload*, avec le Key ID et le Team ID.

   **Un seul envoi, malgré les deux lignes.** Le tableau vide affiche
   « No development APNs auth key » *et* « No production APNs auth key » : c'est
   l'état vide, pas deux emplacements à remplir. Les deux lignes sont un reste de
   l'époque des certificats, où il fallait vraiment un fichier par
   environnement ; une clé d'authentification couvre les deux à elle seule
   (a fortiori configurée en `Sandbox & Production`). Après enregistrement, une
   ligne unique apparaît avec le fichier, le Key ID et le Team ID. Laisser
   *APNs Certificates* vide : c'est l'autre méthode, exclusive. *Web Push
   certificates* ne concerne que le site web (VAPID) et ne sert pas au mobile.

Points qui évitent de refaire le tour deux fois :

- Une seule clé couvre **les deux environnements APNs**, développement et
  production. Il n'y a pas à en charger une par environnement, et l'entitlement
  `aps-environment: production` de l'IPA signé reste valable tel quel.
- La clé est **liée au compte Apple, pas à un bundle id** : le même `.p8` peut
  être chargé dans `adfoot-staging` pour que le workflow `ios-staging` reçoive
  aussi ses notifications.
- Apple limite à **deux clés APNs actives** par compte. S'il y en a déjà deux,
  réutiliser une existante plutôt que d'en créer une troisième.
- Un certificat APNs ferait l'affaire aussi, mais il expire au bout d'un an et
  se renouvelle à la main. La clé n'expire pas.

### Vérifier la chaîne, après coup

Aucune API ne rapporte si la clé APNs est chargée — ni l'API Firebase
Management, ni FCM. Un envoi est la seule chose qui réponde à la question, d'où
`scripts/check-ios-push-delivery.mjs` :

```powershell
# Quels appareils ont un jeton (aucun jeton n'est jamais affiche)
npm.cmd run push:ios:list:production

# Essai a blanc : valide le jeton et la charge utile, ne contacte pas Apple
npm.cmd run push:ios:check:production -- --uid UID_DU_COMPTE

# Envoi reel : la seule preuve. Fait apparaitre une notification.
npm.cmd run push:ios:check:production -- --uid UID_DU_COMPTE --send
```

Sur `THIRD_PARTY_AUTH_ERROR`, le script nomme la cause et le chemin exact de la
console. Il refuse une clé de service d'un autre projet que la cible, refuse de
tourner contre un émulateur, et ne sort jamais la valeur d'un jeton. Le chemin
de la clé vient de `--credentials`, de `GOOGLE_APPLICATION_CREDENTIALS`, ou se
déduit de l'identifiant de projet : aucun chemin de secret n'est écrit dans le
dépôt, et `test/sign_in_never_hangs_guardrails_test.dart` l'impose.

Ordre de validation après le build 45 sur l'iPhone : `push:ios:list:production`
doit montrer une ligne pour le compte iOS — c'est la preuve que le correctif
client aboutit — puis `--send` doit faire apparaître la notification.

## 3. Réseau lent

### La sonde de joignabilité remplaçait la mesure

`NetworkProfileService.detectProfile()` commençait par un `HEAD` vers
`speed.cloudflare.com` avec un budget de **2 secondes**. Un lien 2G ou un 3G
congestionné dépasse ce délai couramment, en fonctionnant très bien — juste
lentement. Cet échec était interprété comme « hors ligne » et **retournait
immédiatement**, sautant `_measureThroughput()`.

Le palier retombait alors sur `_baselineTier`, soit `medium` sur mobile comme
sur Wi-Fi. Donc : sur exactement les connexions qui ont besoin du palier `low`,
l'application se classait `medium` et demandait des rendus 540p, préchargeait
deux voisines et autorisait deux initialisations simultanées, sur un lien qui
n'en soutenait aucune. La vidéo active expirait à 12 s au lieu de 15 s.

Une joignabilité en échec envoie désormais vers la mesure de débit au lieu de
la contourner. Cette sonde a son propre budget (4 s) et traite déjà son propre
dépassement comme une mesure nulle, c'est-à-dire `low` — la bonne réponse. On
ne conclut « hors ligne » que si elle ne produit **aucun** nombre *et* que l'OS
ne rapporte aucun transport. Un cache frais n'est plus préféré à une
joignabilité qui vient d'échouer : c'est une information sur maintenant.

Le drapeau `softProbeFallback`, dont la seule raison d'être était la branche
supprimée, a été retiré (il n'était positionné nulle part).

### Connexion utilisateur

`_signInHandshake` n'avait aucun réessai. Un lien faible ne échoue pas en
bloquant, il échoue en **lâchant** : Firebase Auth répond
`network-request-failed` en une ou deux secondes, et la tentative suivante sur
la même connexion aboutit en général. Sans réessai, cette seule requête perdue
*était* la connexion — l'utilisateur lisait « vérifiez votre connexion » sur
une connexion qui marche, et le seul recours offert était de retaper lui-même.

`_exchangeCredentials` réessaie deux fois (800 ms puis 1,6 s), **uniquement**
sur `_isRetryableSignInFailure` : volontairement plus étroit que
`isTransientAuthFailure`, qui couvre aussi `too-many-requests` — ce code est
Firebase qui demande d'arrêter, et le réessayer est la façon dont un mauvais
réseau devient un compte bloqué. Les dépassements de délai sont exclus pour la
même raison : `_bounded` a déjà attendu 20 s, et en dépenser 20 de plus sur une
connexion qui bloque ne fait que retarder le message utile. Un mot de passe
faux, une adresse inconnue ou un compte désactivé sont des réponses, pas des
échecs : ils remontent dès la première tentative.

### Autres gains

- `ChatRepository.findExistingConversationId` lit d'abord l'identifiant
  déterministe (un document) au lieu de télécharger **toutes** les
  conversations du lecteur à chaque appui sur « Message ». Le balayage reste la
  solution de repli, et reste seul capable de retrouver un identifiant
  historique.
- `ChatRepository.canSendMessage` lit les deux projections en parallèle au lieu
  de deux allers-retours en série.

## 4. On ne voyait plus ce qu'on écrivait, clavier ouvert

`ChatScreen` empile la bannière de contexte du premier contact, l'`Expanded` qui
porte la liste des messages, puis le composeur. La bannière et le composeur ont
une hauteur fixe ; seul l'`Expanded` absorbe la différence.

Dépliée, la bannière fait ~200 dp — titre, contexte, motif, suivi d'agence,
retour participant, bouton « Donner un retour » — et **toutes** les
conversations de cette application en ont une, puisqu'elles passent toutes par
le premier contact guidé. Clavier ouvert, `resizeToAvoidBottomInset` retire la
hauteur du clavier du corps : il ne reste qu'environ 280 dp sur un téléphone
courant. La bannière et le composeur prenaient l'essentiel de la place, et dès
qu'on descend en hauteur d'écran ou qu'on monte en hauteur de clavier (bandeau
de suggestions), **la colonne débordait** : l'`Expanded` tombait à zéro et le
composeur sortait du cadre, sous le clavier.

Le moteur de rendu le dit mot pour mot dans le test de reproduction, à 560 dp
d'écran et 320 dp de clavier : `A RenderFlex overflowed by 84 pixels on the
bottom`.

Correction : la bannière se replie sur une ligne pendant la frappe
(`_buildCollapsedGuidedContextBanner`, déclenchée par
`MediaQuery.viewInsets.bottom > 0`) et rend ~160 dp à la conversation. Elle se
redéploie dès que le clavier se referme : rien n'est perdu, seulement différé.
Le bouton de retour n'est volontairement pas repris dans la version repliée — un
bouton qui change de place quand le clavier s'ouvre est pire que pas de bouton.

### Une hypothèse écartée, et pourquoi elle l'a été

La première piste était un double comptage de l'inset du bas : `ChatScreen`
enveloppe sa colonne dans un `SafeArea` et `MessageInputBar` en a un second,
les deux réclamant le bas. Le test écrit pour la vérifier l'a réfutée :
`MediaQueryData` calcule `padding` comme `viewPadding - viewInsets` borné à
zéro, donc clavier ouvert `padding.bottom` vaut déjà 0 et la hauteur du clavier
n'est jamais comptée deux fois. Un test qui pose `padding.bottom = 48` *et*
`viewInsets.bottom = 300` décrit un état qui n'existe sur aucun appareil — et
c'est en le décrivant qu'on croit voir le bug.

Le `bottom: false` ajouté au `SafeArea` du corps reste : un seul widget doit
posséder l'inset du bas, et c'est le composeur. Mais c'est du rangement, qui ne
gagne que 8 dp clavier fermé — pas la correction du bug signalé.

Tests : `test/chat_composer_keyboard_inset_test.dart`, qui mesure le
débordement réel plutôt que de l'affirmer.

## Révision du candidat

- Version : **1.0.7+45**, commit `2a84c14` sur
  `release/production-device-tests-2026-10-05`, poussé sur GitHub le 11 octobre.
- Témoins du bundle Android relus pour la 45
  (`scripts/aab-content-expectations.json`) : le quatrième témoin est
  `credential exchange dropped; retrying`, seule chaîne littérale non
  interpolée que cette release introduise — les autres correctifs (attente du
  jeton APNs, bannière repliée, palier réseau) sont de la logique et des
  commentaires, absents du snapshot Dart.
- Règles Firestore déjà déployées (10 octobre, 17:39 UTC) : la réparation de la
  messagerie ne dépend pas de ce build.
- Ce que le build 45 apporte et que les règles ne pouvaient pas apporter :
  le jeton APNs sur iOS, la bannière repliée pendant la frappe, le réessai de
  connexion, et le palier réseau correct sur lien lent.

## Candidat Android à importer dans Play Console

- Version : **1.0.7+48**, commit `5011a9b` (`master` et
  `release/production-device-tests-2026-10-05` pointent dessus).
- Artefact : `artifacts/android/adfoot-production-20261011T221809Z.aab`
- Taille : 74 057 587 octets
- SHA-256 : `8dfa7a456caeb1b41d1d85268570003b8868ef1458ee9591ce304d877d83f71e`
- Contenu Dart : les sept témoins présents, instantané différent du bundle
  précédent, bundle postérieur au dernier code Dart.
- Signature : `jarsigner` retourne `jar verified`.
- Alignement : 16 bibliothèques 64 bits à 16 Ko minimum ; ABI arm64-v8a,
  armeabi-v7a, x86_64 ; `extractNativeLibs=false`.

`artifacts/` est dans `.gitignore` : ces bundles sont locaux. Le répertoire
contient les artefacts antérieurs du même jour (45, 46, 47) ; seul
`...T221809Z.aab` correspond au commit courant.

### Un témoin ne doit jamais vivre dans une branche conditionnée par la plateforme

Le contrôle de contenu a refusé le premier bundle 47, et il avait raison. Le
témoin choisi était `notifications/apns_token_absent`, qui vit dans la branche
`if (isApplePlatform && !apnsArrived)` de
`WebMessagingHelper._getMobileToken`. Or `defaultTargetPlatform` est une
**constante de compilation** en release : dans un bundle Android la condition
se replie sur `false` et toute la branche Apple est éliminée par
tree-shaking. La chaîne n'existait donc pas dans le binaire, alors que le code
était bien celui du checkout.

Le témoin retenu est `notifications/fcm_registration_failed`, la branche
`else`, présente sur les deux plateformes. À retenir pour les prochaines
releases : un témoin doit être inconditionnel, sinon la porte refuse un bundle
parfaitement valide.

## 5. Reprise du 12 octobre — build 1.0.7+49

Trois constats du build 48 en test, et pour deux d'entre eux la cause réelle
n'était pas celle qui avait été corrigée.

### 5.1 iOS : rien ne demandait le jeton APNs

Les builds 45, 46 et 47 ont corrigé, chacun, un vrai défaut du chemin APNs —
et aucun ne pouvait aboutir, parce qu'ils supposaient tous que le jeton
finissait par arriver. Il n'était jamais **demandé**.

`registerForRemoteNotifications` n'était appelé par rien. C'est normalement
`FLTFirebaseMessagingPlugin` qui s'en charge, depuis son observateur de
`UIApplicationDidFinishLaunchingNotification`, mais derrière
`if ([FIRMessaging messaging].isAutoInitEnabled)`. Cette garde exige une
application Firebase **par défaut** déjà configurée. Or sur iOS,
`firebase_core` n'en configure une nativement que si `[FIROptions defaultOptions]`
trouve un `GoogleService-Info.plist` **dans le bundle**, et cette application
n'en embarque aucun : la configuration arrive par `--dart-define` et
`Firebase.initializeApp()` côté Dart, bien après cette notification. Donc
`[FIRMessaging messaging]` vaut `nil`, `nil.isAutoInitEnabled` vaut `NO`,
l'enregistrement est sauté — et jamais repris, puisque la mise en place n'a
lieu qu'une fois et que `didReinitializeFirebaseCore` ne fait rien.

Conséquence complète, et elle explique tout l'historique : pas de jeton
d'appareil, donc `getAPNSToken()` rend `nil` indéfiniment, donc `getToken()`
lève `apns-token-not-set` indéfiniment, donc `user_push_tokens` n'a jamais
contenu une seule entrée iOS — pendant qu'Android fonctionnait sans rien de
tout cela, n'ayant pas besoin de cet appel natif précoce.

| Fichier | Effet |
| --- | --- |
| `ios/Runner/AppDelegate.swift` | Appelle `registerForRemoteNotifications()` lui-même, un tour de boucle après `GeneratedPluginRegistrant.register`. N'affiche aucune invite — c'est le rôle de `UNUserNotificationCenter`, et `NotificationService.askPermissionAndUpdateToken` le garde. |
| `test/ios_apns_registration_guardrails_test.dart` | Fixe l'appel **et** sa justification : si un `GoogleService-Info.plist` est un jour ajouté à la cible Runner, le test échoue volontairement, car la garde du plugin passerait alors d'elle-même. |
| `IOS_CODEMAGIC_SETUP_RUNBOOK.md` | La section qui concluait « rien dans le build iOS ne lit ces plists » est corrigée : c'était vrai, et c'était précisément la cause. |

Le différé d'un tour (`DispatchQueue.main.async`) n'est pas cosmétique : le
plugin s'installe comme intercepteur APNs depuis la *notification*
DidFinishLaunching, que UIKit poste seulement après le retour de la méthode.

Un jeton obtenu avant que l'utilisateur accepte n'est pas perdu : le plugin le
met de côté dans `_apnsToken` et l'installe sur FIRMessaging via
`ensureAPNSTokenSetting`, qui tourne avant chaque appel de méthode venu de Dart.

### 5.2 Le champ de saisie du premier message montait trop haut

`Get.bottomSheet` **pose déjà** `Padding(bottom: viewInsets.bottom)` autour du
contenu de la feuille (`GetModalBottomSheetRoute.buildPage`). `ContactIntakeSheet`
ajoutait la même hauteur une seconde fois : clavier ouvert, la feuille était
soulevée de *deux* hauteurs de clavier. Son bas flottait une hauteur de clavier
au-dessus du clavier — le vide noir visible sur les captures, à travers lequel
on voyait la liste des utilisateurs — et ce qui lui restait était écrasé
d'autant, titre et champ de saisie compris.

La correction de la 46 avait borné la *hauteur* de la feuille, ce qui la
ramenait dans le cadre sans retirer le vide sous elle. Cette fois la marge est
rendue à sa route, et l'inset du bas n'est plus réclamé que par le pied de page
— même règle que `ChatScreen` : un seul widget possède le bas.

`showModalBottomSheet` (Flutter) n'ajoute, lui, **aucune** marge de clavier.
C'est la différence entre les deux routes qui produisait le défaut, et
`test/contact_intake_sheet_keyboard_test.dart` la verrouille : la géométrie
cassée est reproduite, la corrigée est mesurée, et un test refuse qu'une
future feuille soit ouverte autrement que par `Get.bottomSheet`.

### 5.3 Réseau lent : la connexion, puis la lecture

**Connexion.** `_signInHandshake` dépensait **sept allers-retours réseau** en
série avant que la session puisse se résoudre : l'échange d'identifiants,
`reload()`, `getIdToken(true)`, puis `_refreshCurrentUserAfterVerification`,
qui commence par *un autre* `getIdToken(true)` et `reload()` et, trouvant
l'adresse vérifiée, refait les deux une troisième fois. Quatre de ces sept ne
servaient qu'au compte vérifié quelques secondes plus tôt — celui qui vient de
cliquer le lien dans son application de courrier. Pour une connexion ordinaire,
l'indicateur était déjà vrai au `reload()` de la deuxième étape, et la poursuite
le relisait trois fois pour s'entendre dire la même chose : douze secondes de
rouet sur un lien à 3 s d'aller-retour, sur le seul écran qu'on ne peut pas
contourner.

La poursuite n'est désormais engagée que s'il y a quelque chose à poursuivre.
Le chemin « pas encore vérifié » est inchangé : il garde ses trois tentatives
et sa seconde d'espacement.

**Lecture vidéo.** Deux seuils étaient restés fixes alors que tout le reste du
pipeline suit le palier mesuré : la limite de première image (6 s) et les
strikes de mise en tampon avant première image (8 × 700 ms). Tous deux sont
appliqués **après** une initialisation réussie, et tous deux finissent par une
reconstruction du lecteur qui **jette ce qui avait déjà été téléchargé**. Sur
un lien `low`, dont la limite d'initialisation est déjà à 15 s, le lecteur
terminait une init légitime, commençait à remplir son tampon, et se faisait
démolir à 6 s — trois fois, soit le budget de reprise automatique — après quoi
l'utilisateur voyait une erreur de lecture pour une vidéo qui arrivait très
bien, juste lentement. Plus le lien était lent, plus l'échec était certain.

Les deux budgets rejoignent `VideoNetworkTuning` (6 s / 9 s / 16 s, et
8 / 12 / 22 strikes) et sont lus au moment où chaque chien de garde est armé,
donc un palier re-mesuré en cours de session s'applique dès la vidéo suivante.

### 5.4 Ce que l'échec de notification dit désormais de lui-même

`notifyVideoOwner` renvoyait un `false` muet quand l'auteur n'avait aucun
appareil enregistré — le cas le plus fréquent, et celui qui est derrière « la
vidéo est validée et le joueur n'est notifié de rien ». L'absence de trace se
lisait comme une absence de problème.

- Chaque branche se signale maintenant, et le résultat (`notifyOutcome`) est
  rendu à `adminSetVideoStatus` : la personne qui a cliqué « approuver » est la
  seule en position de prévenir le joueur autrement.
- `messaging/third-party-auth-error` — « j'ai un jeton, mais aucun moyen de
  joindre Apple » — est distingué d'un jeton mort et journalisé en `error` avec
  le chemin exact de la console. C'est la seule panne de cette chaîne que rien
  d'autre ne peut faire apparaître, et elle est aussi comptée en masse dans le
  fanout, où elle frappe tous les destinataires iOS d'un coup.
- `user_push_tokens` enregistre `platform` et `appVersion`, donc
  `npm run push:ios:list:production` répond directement à « un iPhone s'est-il
  déjà enregistré ? » au lieu de le faire déduire. Les lignes antérieures à la
  49 rapportent `platform: unknown`, et le script le dit plutôt que de laisser
  confondre « aucun iPhone » avec « pas encore d'information ».

### 5.5 Les vidéos d'un profil n'avaient aucune miniature

Le document d'une vidéo portait `thumbnailPath` — un *chemin* Storage,
`thumbnails/thumbnail_<id>.jpg` — et pas `thumbnail`, l'URL qu'un client peut
aller chercher. Deux défauts se superposaient.

**Côté serveur, une course que personne ne rattrapait.** L'URL n'avait qu'un
seul écrivain : `optimizeMp4Video`, après FFmpeg. Cette fonction est déclenchée
par l'arrivée de l'objet **vidéo** dans Storage, alors que le client téléverse
la miniature *ensuite* — la séquence réelle est : vidéo (l'optimiseur démarre),
puis ticket de miniature, puis miniature, puis `finalizeUpload`. Sur un clip
léger ou une connexion faible, l'optimiseur atteignait
`tryResolveThumbnailPath` avant que la miniature existe, écrivait
`...(thumbnail ? {thumbnail} : {})` — donc rien — et plus personne ne regardait
jamais : aucun déclencheur ne se déclenche pour `thumbnails/`, et
`finalizeUpload` ne notait que le chemin.

C'est exactement la course décrite dans le commentaire d'`isFinalizedUploadSession`
pour la description et la légende. Celle-là avait été fermée côté finalize ;
celle de la miniature, non.

**Côté client, un chemin pris pour une adresse.** `Video.fromMap` acceptait
`thumbnailPath` en dernier recours. La valeur n'était donc pas vide, et
`profile_screen_widgets` prenait la branche `CachedNetworkImage` avec une
chaîne condamnée : échec, `errorWidget`, icône de repli — au prix d'une
résolution réseau ratée par tuile et par reconstruction, précisément ce que le
commentaire de ce widget dit vouloir éviter.

Le fil d'actualité masquait le défaut : la miniature n'y est qu'un placeholder
fugace avant que la vidéo s'affiche. Dans la grille d'un profil, c'est la seule
chose affichée — d'où « les vidéos sont affichées sans miniatures ».

| Fichier | Effet |
| --- | --- |
| `functions/src/storage_download_url.ts` (nouveau) | `ensureDownloadToken` et `buildStorageDownloadUrl` sortent d'`index.ts` (import circulaire autrement), et `resolveThumbnailDownloadUrl` devient la résolution partagée : chemin enregistré, puis les trois noms conventionnels, puis le jeton. |
| `functions/src/upload_session.ts` | `finalizeUpload` résout et écrit l'URL. C'est le second écrivain, et le seul qui ne peut pas perdre la course : le client téléverse la miniature avant de l'appeler. Résolu **avant** la transaction — c'est de l'I/O Storage, et un corps de transaction peut être rejoué. |
| `functions/src/index.ts` | L'optimiseur passe par la même résolution ; perdre la course ne coûte plus rien. |
| `lib/models/video.dart` | Seule une URL `http(s)` est retenue. Un chemin rend la chaîne vide, donc la tuile affiche son repli immédiatement. Un document ancien dont `thumbnailPath` contiendrait déjà une URL reste accepté : c'est la forme qui décide, pas le nom du champ. |
| `scripts/repair-video-thumbnails.mjs` (nouveau) | Répare les vidéos déjà publiées — rien ne relance l'optimiseur. `npm run thumbnails:check:production` pour voir, `thumbnails:repair:production` pour écrire. Une vidéo dont la miniature n'existe réellement pas est signalée et laissée telle quelle : inventer une URL transformerait un repli propre en image cassée. |

Le jeton de téléchargement est idempotent (relu avant d'être émis), donc les
deux écrivains produisent la même URL et ne peuvent pas se contredire.

Verrouillé par `test/video_thumbnail_guardrails_test.dart`.

**À faire après le déploiement des Functions :**

```powershell
npm.cmd run thumbnails:check:production    # essai a blanc
npm.cmd run thumbnails:repair:production   # ecrit
```

### 5.6 Seconde vérification — deux défauts introduits par les correctifs eux-mêmes

Une relecture des diffs, et non une relecture des tests : les deux points
ci-dessous passaient toutes les portes.

**Une pile d'appels entière par entrée de journal.** `AppLogger._safeMetadata`
ne tronquait rien. `logClientEvents` plafonne le *message* à 2000 caractères,
mais les métadonnées — où vivent `error.toString()` et surtout
`stackTrace.toString()`, couramment plusieurs kilo-octets en release — étaient
recopiées telles quelles dans Firestore.

Tant que les avertissements étaient échantillonnés à 15 %, le volume était
borné par accident. Le correctif 1.2 a retiré ce frein sans en poser d'autre :
117 sites d'avertissement, chacun pouvant expédier une pile complète, sur des
flux qui se redéclenchent à chaque snapshot. Les garde-fous existants
(20 appels/min, 200 entrées en tampon, expiration automatique) bornent le
*nombre* d'entrées, jamais leur taille.

`maxMetadataValueLength = 2000`, même plafond que le message, avec une marque
explicite quand la valeur est coupée — une pile tronquée en silence se lit
comme une pile courte.

**Un script de réparation qui réordonnait les profils.**
`repair-video-thumbnails.mjs` écrivait `updatedAt: serverTimestamp()` à côté de
l'URL de miniature, par habitude. Or `ProfileRepository.fetchUserVideos` trie la
grille d'un joueur par `updatedAt` décroissant, et le fil public retombe sur ce
même champ dès que son index propre est indisponible
(`VideoRepository._legacyOrderField`).

La réparation aurait donc remonté en tête de chaque profil les vidéos réparées,
dans l'ordre où le script a parcouru la collection — en remplaçant un défaut
visible par un désordre invisible. Le champ n'est plus écrit : un remplissage
de champ dérivé ne doit rien déplacer.

Rien d'autre n'a bougé à la seconde passe, mais trois points ont été
explicitement vérifiés plutôt que supposés :

- `finalizeUpload` résout la miniature **après** `validateThumbnail`, qui a
  déjà prouvé l'existence de l'objet dans `storage.bucket()`. L'URL est donc
  construite depuis le bucket où sont réellement les octets, ce qui ferme le
  piège `appspot.com` / `firebasestorage.app`.
- `late final VideoManager _videoManager` est affecté dans `initState` avant
  que le moindre chien de garde puisse lire les budgets qui en dépendent.
- Aucune référence ne subsiste aux symboles retirés (`tryResolveThumbnailPath`,
  `handlePushSendError`, `isUnregisteredTokenError`,
  `warmAppVersionForTokenContext`), et une bannière de section orpheline
  laissée par l'extraction des helpers a été retirée d'`index.ts`.

### 5.7 Notifications iOS — résolu de bout en bout, 13 octobre

`check-ios-push-delivery --send` répond `Delivered to FCM`, et la notification
apparaît sur l'iPhone. C'est la première fois depuis l'existence du projet.

La chaîne complète, chaque maillon prouvé par une donnée et non par un
raisonnement :

| Étape | Preuve |
| --- | --- |
| L'enregistrement APNs est demandé | correctif `AppDelegate`, build 1.0.7+49 |
| Le jeton d'appareil arrive | plus aucun `notifications/apns_token_absent` sur 49 |
| Le jeton FCM est émis et stocké | `user_push_tokens` : `platform=ios build=1.0.7+49` |
| FCM authentifie auprès d'Apple | la clé APNs corrigée dans la console |
| La remise aboutit | notification visible sur l'appareil |

**La panne avait deux causes indépendantes, et chacune masquait l'autre.** Tant
qu'aucun jeton n'existait, un envoi répondait `token_missing` et n'atteignait
jamais Apple — la clé invalide était donc indétectable. Une fois le jeton
obtenu, elle est apparue en une commande. C'est la raison pour laquelle
l'enquête a traversé quatre builds : un symptôme unique, « aucune notification
sur iOS », recouvrait deux pannes à des étages différents.

Ce qui a rendu la fin rapide mérite d'être noté, parce que c'est reproductible :

- la colonne `build` dans `client_logs`, qui a permis de dire « toutes les
  erreurs APNs sont antérieures à la 49 » au lieu de le déduire ;
- les cinq sources `notifications/*` passées en `error`, qui ne sont plus
  échantillonnées ni muettes ;
- `check-ios-push-delivery --send`, qui nomme `third-party-auth-error` et
  donne le chemin exact de la console plutôt qu'un code.

Le diagnostic final a tenu en deux commandes, là où les trois builds
précédents avaient avancé par élimination.

**La cause exacte, pour le prochain renouvellement de clé.** La clé APNs
*était* présente dans la console depuis les 10-11 octobre, et Apple la
refusait quand même (`Invalid APNs credential`). Ce qui l'a réglée : **re-saisir
l'ensemble `.p8` + Team ID + Key ID**. Le premier téléversement était donc
incomplet ou mal apparié, sans que rien ne le signale — la console accepte un
trio incohérent et n'en dit rien jusqu'au premier envoi réel.

À retenir : « la clé est dans la console » n'est pas une vérification. Seul
`check-ios-push-delivery --send` en est une, et c'est la raison d'être de ce
script.

**Le parcours d'origine est validé :** une vidéo approuvée depuis le portail
déclenche bien la notification « Vidéo approuvée » sur l'iPhone de l'auteur.
C'est la plainte qui a ouvert ce dossier.

**Reste à vérifier :** `adfoot-staging` est un projet Firebase **séparé**
(sender `467972880318`, bundle `org.adfoot.app.staging`). Si la même `.p8` n'y
a pas été téléversée aussi, les builds staging resteront muets sur iOS,
exactement de la même façon — et la prochaine enquête repartira de zéro.

**Relevé du 13 octobre 2026 — staging ne peut pas encore être tranché, et
c'est une limite de méthode, pas un résultat.**

```
user_push_tokens in adfoot-staging: 0
No device has registered a token. Nothing can be delivered to anyone.
```

Zéro jeton ne distingue pas « la clé APNs manque » de « aucun appareil n'a
lancé de build staging récemment ». Les deux produisent le même zéro, et comme
le note la section 5 plus haut, aucune API ne rapporte si la clé est chargée.
La seule mesure qui sépare les deux cas est un envoi réel : installer un build
`ios-staging`, ouvrir l'application une fois, puis

```powershell
npm.cmd run push:ios:list:staging
npm.cmd run push:ios:check:staging -- --uid <UID> --send
```

Une ligne `platform=ios` prouve que l'enregistrement APNs aboutit ;
`THIRD_PARTY_AUTH_ERROR` au moment de l'envoi prouve que la clé manque pour
`org.adfoot.app.staging` et le script nomme alors le chemin de console. Tant
qu'aucun build staging n'est installé, ce point reste ouvert sans être un
défaut — et il ne bloque pas la production, dont la preuve est acquise
ci-dessous.

Ces deux scripts npm n'existaient pas : `scripts/check-ios-push-delivery.mjs`
acceptait déjà `--environment staging`, mais aucun raccourci ne l'exposait, si
bien que la vérification supposait de connaître l'option. Ils attendent la clé
ops à l'emplacement conventionnel `.credentials/adfoot-staging-ops.json`
(comme `adfoot-production-ops.json` pour la production) ; la clé staging
présente sur ce poste porte encore son nom de téléchargement
`adfoot-staging-firebase-adminsdk-*.json`. La copier sous le nom conventionnel,
ou passer `--credentials <chemin>`.

### Portes passées localement, le 12 octobre

| Contrôle | Résultat |
| --- | --- |
| `flutter analyze` | 0 problème |
| `flutter test` | **1031** tests réussis (976 avant, +55) |
| `functions` lint + `tsc` | réussis |
| `scripts/check-admin-mobile-contract.ps1` | réussi |
| `scripts/check-ios-release-readiness.ps1` | réussi |

### Ce qui restait à prouver sur l'appareil — résolu

Cette section listait trois preuves à faire. **Les trois sont faites**, et
l'étaient déjà quand le tableau « La chaîne complète est prouvée » plus haut a
été écrit : la liste n'avait pas été retirée, si bien que le document
s'opposait à lui-même. C'est la seconde fois dans ce dépôt qu'un relevé d'état
périmé survit à sa propre résolution ; voir le même défaut, et la même
correction, dans `public-profile-rollout-2026-09-28.md`.

1. Jeton `platform=ios` stocké — voir le tableau de la section 5.
2. Envoi direct reçu — même tableau, ligne « La remise aboutit ».
3. Notification « Vidéo approuvée » après approbation depuis le portail — voir
   « Le parcours d'origine est validé ».

**Reconfirmé en direct le 13 octobre 2026**, parce qu'un relevé consigné et un
relevé reproductible ne se valent pas : `npm.cmd run push:ios:list:production`
rapporte trois jetons, dont

```
Fszb…Pkr2  role=joueur  token=present  platform=ios
           build=1.0.7+49  updatedAt=2026-10-13T03:29:54Z
```

Les deux autres restent `platform=unknown` : ce sont des enregistrements
antérieurs au champ `platform`, pas des échecs.

Ne reste donc que staging, traité à la fin de la section 5 — et qui ne bloque
pas la production.

## Ordre de déploiement

Conforme à `CLAUDE.md` — les règles d'abord, le mobile ensuite :

```powershell
# 1. Règles Firestore (valide la compilation côté serveur avant publication)
firebase.cmd deploy --only firestore:rules --project adfoot-production

# 2. Cloud Functions (texte des notifications de modération)
.\scripts\deploy-functions-safe.ps1

# 3. Contrôle de parité avant le build mobile
.\scripts\check-backend-parity.ps1
```

Le portail admin n'est pas affecté : les clauses `isAdminOperator()` de
`public_profiles` et `contact_intakes` sont préservées à l'identique, et
`blocks` / `conversations` n'ont jamais été lues par le portail via le SDK
client.

## Portes passées localement, le 10 octobre

| Contrôle | Résultat |
| --- | --- |
| `flutter analyze` | 0 problème |
| `flutter test` | 976 tests réussis (959 avant, +17) |
| `functions` lint + `tsc` | réussis |
| `functions` tests | 15 réussis |
| `scripts/audit-source-encoding.mjs functions/src lib` | 0 constat |
| `scripts/check-admin-mobile-contract.ps1` | réussi |

| `npm run rules:test` (émulateur) | **113/113** conformes |
| `npm run rules:test:storage` | **30/30** conformes |
| `check-backend-parity.ps1` | règles et index identiques au dépôt |

### Faire tourner l'émulateur de règles sur cette machine

`firebase-tools` 15.30 refuse de démarrer sous Java 21, et le JDK du `PATH` est
Temurin 17. Le JBR livré avec Android Studio est en Java 25 : il suffit de le
désigner, aucune installation n'est nécessaire.

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
npm.cmd run rules:test
npm.cmd run rules:test:storage
```

C'est le contrôle le plus utile de ce dépôt, et il était inexécutable depuis un
mois pour cette seule raison.

### Si `.ps1` est refusé dans votre terminal

`Get-ExecutionPolicy -List` renvoie `Undefined` partout, donc le défaut
`Restricted` s'applique et aucun script du dépôt ne démarre. Une fois pour
toutes, sans droits administrateur :

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

ou, ponctuellement : `powershell -ExecutionPolicy Bypass -File .\scripts\<script>.ps1`.

(Le préfixe `!` n'est pas un opérateur PowerShell — il ne vaut que dans
l'invite de Claude Code.)
