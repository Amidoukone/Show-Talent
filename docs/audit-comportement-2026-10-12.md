# Audit de comportement avant le build 49 — 12 octobre 2026

## Portée et méthode

Revue du checkout courant (`release/production-device-tests-2026-10-05`, après
les corrections du 12 octobre), côté application Flutter et Cloud Functions.
Ce qui a réellement été exécuté, et qui fixe le niveau de confiance :

| Contrôle | Portée |
| --- | --- |
| `flutter analyze` avec 14 lints de correction activés temporairement (`cancel_subscriptions`, `close_sinks`, `unawaited_futures`, `throw_in_finally`, `only_throw_errors`, `hash_and_equals`…) | 180 fichiers Dart, 75 000 lignes |
| Balayage des blocs `catch` vides et des `catch` qui ne rapportent qu'en `debug` | `lib/` entier |
| Balayage des requêtes Firestore sans `.limit()` | `lib/` et `functions/src/` |
| Balayage des littérales utilisateur non localisées | `lib/screens`, `lib/widgets`, `lib/controller` |
| Lecture du chemin complet : démarrage, session, fil vidéo, lecture, messagerie, profil, réglages, suppression de compte | ciblée |
| `flutter test` (1012 avant l'audit, **1023** après les correctifs ci-dessous), `functions` lint + `tsc` + tests (15), `audit-source-encoding`, `check-admin-mobile-contract`, `check-ios-release-readiness` | tous verts |

Aucun service distant n'a été interrogé : les scripts qui envoient ou lisent en
production sont bloqués depuis cet environnement. Les conclusions ci-dessous
sont donc établies sur le code, jamais sur l'état réel du backend.

## Ce qui est sain — constaté, pour ne pas le réauditer

Autant que les défauts, ces points méritent d'être consignés : ils ont été
vérifiés et n'ont pas besoin d'être repris.

- **Aucune souscription non annulée.** `cancel_subscriptions` ne remonte rien
  sur 29 `listen()`. Les deux signalements de `close_sinks`
  (`profile_repository.dart:413`, `video_repository.dart:133`) sont des faux
  positifs : les deux `StreamController` annulent dans leur `onCancel`.
- **Rien ne lève dans un `finally`, rien ne jette de non-`Error`, aucun
  `hashCode`/`==` dépareillé.**
- **La gestion d'erreur globale est complète** : `runZonedGuarded` autour de
  `main`, `FlutterError.onError` vers Crashlytics, et un écran de reprise si
  le bootstrap échoue — un cas où beaucoup d'applications se ferment sans un
  mot.
- **L'internationalisation est faite.** Sur ~1 200 chaînes d'interface, deux
  littérales françaises subsistent (`push_notification.dart`, messages jamais
  affichés : `toast: ToastLevel.none`), et les valeurs par défaut
  d'`AdStatePanel` sont déjà documentées comme inatteignables.
- **App Check en `soft` est une décision correcte, pas une dette.** Play
  Integrity échoue sur une part réelle du parc visé, et ce que l'upload exige
  vraiment — jeton d'identité, rôle, quotas transactionnels, URL signées
  courtes, propriété vérifiée — est entièrement côté serveur. Voir
  `MOBILE_APPCHECK_VALIDATION_RUNBOOK.md`.
- **Le piège des champs absents dans les règles Firestore est traité** : les
  compteurs (`vues`, `views`, `shareCount`, `likes`, `reports`) passent tous
  par un `("champ" in resource.data) ? … : défaut`.

---

## 1. Erreurs silencieuses

### 1.1 `client_logs` ne dit ni quelle version ni quelle plateforme — P1

`ClientLogger._deviceContext()` n'envoie que `{platform}`. `logClientEvents`
range ce contexte tel quel, et `scripts/list-recent-client-errors.mjs` ne
l'affiche jamais. **Aucune erreur de production n'est donc attribuable à un
build.**

Ce n'est pas théorique : c'est exactement ce qui a coûté quatre builds sur les
notifications iOS. Le registre de décision en garde la trace — « aucune
occurrence depuis l'installation de la 45, *c'est comme ça qu'on sait* que la
45 est sur l'appareil ». Une déduction par élimination, là où un champ aurait
répondu.

**Correctif :** ajouter `appVersion` et `env` au contexte, et les afficher dans
le script de lecture. Additif, aucun changement de comportement.

### 1.2 Les avertissements sont échantillonnés à 15 % pendant la phase de test — P1

`AppLogger.productionWarningSampleRate = 0.15`. Le dépôt compte **117 appels
`AppLogger.warning`** contre 17 `AppLogger.error`. Cinq occurrences sur six
sont donc jetées avant d'être envoyées.

C'est un bon réglage pour une application installée des milliers de fois. Avec
trois testeurs, c'est l'inverse d'un réglage : un défaut qui survient une fois
par session est vu environ une session sur sept, et l'absence de trace se lit
comme une absence de problème. Le registre contient déjà deux fois le
raisonnement « il n'a rien journalisé — mais les avertissements sont
échantillonnés à 15 %, donc ce silence n'était pas une preuve ».

Le coût de passer à 1.0 est borné de trois côtés : 20 appels/minute/utilisateur
(`enforceCallRateLimit`), 50 entrées par appel, et une expiration automatique
(90 jours pour les erreurs, 30 pour la télémétrie).

**Correctif :** monter le taux à 1.0 pendant la fenêtre de test et de
lancement, le redescendre quand le volume d'installations le justifiera. Un
`--dart-define` permettrait de le faire sans toucher au code.

### 1.3 Trente-six `catch` ne rapportent qu'en `debug` — P1

`AppLogger.debug` sort immédiatement de `_shouldSendToRemote` : **rien n'est
jamais envoyé.** La plupart des 36 sites sont du nettoyage légitime (cache
vidéo, `dispose`). Sept ne le sont pas — l'utilisateur y voit une erreur, nous
non :

| Site | Ce que l'utilisateur voit | Ce que nous voyons |
| --- | --- | --- |
| `edit_profil_screen.dart:563` | « Enregistrement impossible » | rien |
| `edit_profil_screen.dart:1059` | « Ajout du CV impossible » | rien |
| `profile_controller.dart:364` | « Profil indisponible » | rien |
| `setting_screen.dart:96` | écran des réglages inutilisable | rien |
| `setting_screen.dart:138` | « Enregistrement impossible » (confidentialité) | rien |
| `setting_screen.dart:252` | « Enregistrement impossible » (langue) | rien |
| `home_screen.dart:160` | **la mauvaise vidéo** | rien |

La dernière mérite d'être lue deux fois. `_ensureFocusedVideoVisible` est le
chemin qu'emprunte l'appui sur une notification de modération :
`fetchReadyVideoById` échoue, la fonction rend `0`, et l'utilisateur atterrit
en haut du fil au lieu de sa vidéo. Aucune erreur affichée, aucune trace. Nous
venons de passer deux jours à faire *arriver* cette notification ; son appui
peut échouer en silence.

**Correctif :** passer ces sept en `AppLogger.error` avec une `source` stable.
C'est le standard que le dépôt s'est déjà donné ailleurs (« une capacité
perdue n'est pas du bruit dont on prend un échantillon »).

### 1.4 Le tampon de journalisation ne survit pas à la mort du processus — P3

`ClientLogger` garde ses entrées en mémoire, vidées toutes les 3 s ou tous les
10 éléments. L'erreur journalisée juste avant un crash ou un *kill* système —
celle qu'on veut le plus — est celle qui a le plus de chances d'être perdue.
Crashlytics couvre le crash lui-même, pas les journaux applicatifs qui le
précèdent.

Correctif possible, pas avant la 49 : persister le tampon dans
`SharedPreferences` et le rejouer au démarrage suivant.

---

## 2. Incohérences

### 2.1 Deux sources de vérité pour les abonnements — P2

Les relations vivent à la fois dans les sous-collections
`users/{uid}/following` et `followers`, **et** dans les tableaux
`followingsList` / `followersList` du document utilisateur. Le code des
Functions qualifie les tableaux de « compatibilité pendant que la migration
ponctuelle tourne encore » — formulation présente depuis fin septembre.

Tant que les deux coexistent, chaque écriture doit toucher les deux
(`follow_actions.ts` le fait), chaque suppression de compte aussi
(`cleanupFollowReferences` lit les deux), et une divergence entre les deux ne
se voit nulle part. Le compteur `followers` affiché sur une fiche en dépend.

**À décider :** terminer la migration et retirer les tableaux, ou acter qu'ils
restent et écrire pourquoi. L'état actuel — « en cours » depuis trois
semaines — est le seul qui coûte sans rien rapporter.

### 2.2 Deux lectures du manifeste de version — P3

`AppVersionLabel` et (depuis aujourd'hui) `UserRepository` appellent chacun
`PackageInfo.fromPlatform()`. Le correctif 1.1 en ajouterait un troisième.
Une seule source, lue une fois par processus, serait plus juste — et c'est
elle que les trois consommateurs devraient interroger.

---

## 3. Optimisations

### 3.1 Le préchargement des miniatures ignore le débit mesuré — P2

Tout le reste du pipeline de lecture recule sur un lien lent : `preloadRadius`
tombe à 0 sur le palier `low`, et `PlaybackBandwidthArbiter` retient les
préchargements tant que la vidéo visible streame — « la vidéo à l'écran ne
doit pas concourir avec ses propres voisines ».

`_thumbnailPrefetchRadius` est resté une constante à 2. À chaque changement de
page, `VideoFeedPager` déclenche jusqu'à cinq téléchargements d'images **avant**
d'appeler `onIndexChanged`, c'est-à-dire avant même que la vidéo attendue
commence son initialisation. En régime établi la déduplication ramène cela à
deux images par balayage, mais elles passent toujours devant, et sur le palier
où le pipeline a explicitement décidé de ne plus rien précharger.

**Correctif :** faire suivre le rayon au palier, comme `preloadRadius`
(2 / 2 / 1). Pas 0 : sur un lien lent la miniature est précisément ce qui évite
un écran noir pendant la mise en tampon.

### 3.2 La suppression de compte lit séquentiellement, document par document — P2

`cleanupFollowReferences` (`admin_account_actions.ts`) boucle sur chaque
relation et fait un `await targetRef.get()` puis un `await update()` **dans la
boucle**. Pour un compte suivant 300 personnes, cela fait 300 allers-retours en
série, deux fois (sortants puis entrants), auxquels s'ajoutent les vidéos, le
Storage, les conversations et leurs messages — eux aussi lus sans borne.

Le budget est déjà porté à 300 s pour `deleteOwnAccount`, et le commentaire du
code reconnaît le risque. Mais la suppression de compte est une exigence App
Store (5.1.1(v)) et un échec à mi-parcours laisse un compte à moitié effacé.

**Correctif :** grouper les lectures (`db.getAll`) et paralléliser les
écritures par lots. Mécanique, sans changement de sémantique.

### 3.3 `watchFollowingIds` écoute toute la sous-collection, sans borne — P3

`FollowController` maintient un écouteur permanent sur
`users/{uid}/following where active == true`, sans `.limit()`, pour alimenter
l'état du bouton « Suivre ». Un recruteur suivant 500 joueurs paie 500 lectures
Firestore à chaque démarrage à froid. Supportable au lancement, à surveiller.

---

## Ce qui a été corrigé dans la 1.0.7+49

Les quatre points retenus, tous appliqués et verrouillés par des tests.

| # | Correctif | Garde-fou |
| --- | --- | --- |
| 1.1 | `lib/services/app_version.dart` : une seule lecture du manifeste pour tout le processus, partagée par le libellé de version, le document de jeton push et `client_logs`, qui porte désormais `appVersion`, `platform` et `env`. `list-recent-client-errors.mjs` affiche le build de chaque entrée et un décompte par build en tête de rapport. | `observability_reach_guardrails_test` — le contexte porte les trois champs, et aucun autre fichier de `lib/` n'appelle `PackageInfo.fromPlatform` |
| 1.3 | Les sept `catch` passés en `AppLogger.error` avec une `source` stable : `profile/save`, `profile/cv_upload`, `profile/watch`, `settings/load`, `settings/privacy`, `settings/language`, `feed/focus_video`. L'arbitrage entre `error` et `warning` est maintenant écrit une fois, sur `AppLogger.error`. | `observability_reach_guardrails_test` — une `source` épinglée par site, et l'appel qui la précède doit être `AppLogger.error` |
| 1.2 | `CLIENT_LOG_WARNING_SAMPLE_PERCENT`, défaut **100**. Les huit commentaires qui citaient « 15 % » en dur ne mentent plus. | `observability_reach_guardrails_test` — le taux dérive du réglage, pas d'un chiffre écrit deux fois |
| 3.1 | `thumbnailPrefetchRadius` rejoint `VideoNetworkTuning` (2 / 2 / **1**), lu au moment du préchargement. | `video_architecture_test` — le rayon décroît avec le palier, et ne descend jamais à 0 |

Deux témoins de bundle ont été ajoutés à `scripts/aab-content-expectations.json`
(`feed/focus_video`, `settings/privacy`) : inconditionnels, donc à l'abri du
*tree-shaking* qui avait fait refuser le premier bundle 47.

### À rétablir avant le déploiement public

**`CLIENT_LOG_WARNING_SAMPLE_PERCENT` est à 100.** C'est le bon réglage pour
trois testeurs et le mauvais pour des milliers d'installations : 117 sites
d'avertissement écrivant dans Firestore sans échantillonnage, cela se paie.

Redescendre sans toucher au code, au moment du passage public :

```
flutter build appbundle --release --flavor production   --dart-define=CLIENT_LOG_WARNING_SAMPLE_PERCENT=15
```

ou repasser le défaut à 15 dans `AppLogger`. C'est une entrée de la liste de
contrôle avant publication, pas une décision à reprendre dans le code.

## Ce qui reste, sur décision

Après la 49 : **2.1** (migration des tableaux d'abonnement), **3.2**
(suppression de compte), **1.4** (tampon de journalisation persistant),
**3.3** (`watchFollowingIds`).

Une tranche suivante pour 1.3, non traitée ici parce qu'elle demande un
arbitrage par site plutôt qu'une règle : les `catch` en `debug` restants dans
`lib/services` et `lib/l10n`. Les deux qui méritent un regard —
`locale_preference.set` (la langue choisie ne survit pas au redémarrage, et
rien ne le dit) et `feature_flag_service.fetchConfig` (le streaming adaptatif
retombe silencieusement sur ses défauts). Les autres — les déconnexions
best-effort avant navigation, les jetons App Check — sont délibérés.

Le garde-fou `observability_reach_guardrails_test` ne couvre aujourd'hui que
`lib/controller`. L'étendre à `lib/screens` est possible dès maintenant : les
sept sites corrigés l'ont vidé de sa dette, à quatre déconnexions
best-effort près.
