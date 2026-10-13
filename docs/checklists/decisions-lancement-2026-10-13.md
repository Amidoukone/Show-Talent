# Décisions de lancement — relevé du 13 octobre 2026

Quatre décisions restaient ouvertes avant la soumission finale Android et iOS.
Trois sont tranchées par une mesure ; une seule demande encore une action
humaine, et ce n'est pas celle qui paraissait la plus urgente.

Tout ce qui suit a été relevé en lecture seule depuis le checkout
`release/production-device-tests-2026-10-05`, avec la clé ops
`.credentials/adfoot-production-ops.json`. Aucun déploiement n'a été fait.

## Tableau de bord

| # | Décision | État au 13 octobre | Action restante |
| --- | --- | --- | --- |
| 1 | Quelles règles sont réellement déployées | **Répondu.** Règles finales en production depuis le 2026-10-10 | aucune |
| 2 | Compte de démonstration App Review | **Confirmé nécessaire, et absent** | créer le compte, renseigner les deux consoles |
| 3 | Fermer la migration `public_profiles` | **Mesuré (8 champs vides) et préparé** | lancer `functions:deploy:production` depuis ce poste |
| 4 | `.p8` APNs sur `adfoot-staging` | **Indécidable en l'état** — et non bloquant ; la production est prouvée | installer un build staging pour trancher |

## 1. Les règles déployées — répondu, rien à faire

C'était la seule question dont personne ne connaissait la réponse.

```powershell
npm.cmd run backend:parity:check:production
```

| Contrôle | Résultat |
| --- | --- |
| Firestore : déployé vs `firestore.rules` | **identique**, SHA256 `da5f5bd9…6dd6`, `updateTime` 2026-10-10T17:39:34Z |
| Storage : déployé vs `storage.rules` | **identique**, SHA256 `1a81175d…2be4`, `updateTime` 2026-10-05T10:00:18Z |
| Index déclarés / déployés | **44 / 44**, tous `READY`, aucun en trop |
| TTL `client_logs`, `video_action_logs` | **ACTIVE** |

Le contrôle sort en code 0. Le backend déployé est exactement ce dépôt : un
build publié maintenant ne s'appuie sur rien qui n'existe pas encore.

Ce résultat corrige au passage une documentation devenue fausse. La checklist
`public-profile-rollout-2026-09-28.md` décrivait encore une production sous
règles **transitoires**, relevé du 2 octobre à l'appui. Un opérateur qui aurait
suivi ce document aurait redéployé les règles transitoires et réouvert une
exposition des profils plus large que prévu. Le document porte désormais un
avertissement en tête et la mesure du 13 octobre.

## 2. Compte de démonstration App Review — la seule action vraiment urgente

Vérifié dans le code, pas supposé :

- `publicSelfSignupRoles` (`lib/utils/account_role_policy.dart`) est la **liste
  vide**.
- `lib/screens/signup_screen.dart` n'est pas un formulaire : un logo, trois
  cartes explicatives, un bouton de retour.
- Les cinq rôles — `joueur`, `fan`, `club`, `recruteur`, `agent` — sont tous
  provisionnés par un administrateur.

Un reviewer qui ouvre l'application n'atteint donc **rien** sans identifiants.
C'est le rejet Guideline 2.1 standard, et il coûte un cycle de revue complet.
Le même trou existe côté Google : la déclaration *App access* de la Play
Console est à « tout est accessible » par défaut, ce qui est faux pour cette
application.

Le piège à connaître avant de créer le compte : **ne pas le créer à la main
dans la console Firebase Auth.** `cleanupUnverifiedAccounts` tourne toutes les
24 h et supprime les comptes de plus de trois jours
(`UNVERIFIED_ACCOUNT_RETENTION_DAYS=3`). L'exemption ne s'applique qu'aux
comptes reconnus par `asManagedAccount()`, c'est-à-dire portant
`createdByAdmin === true` ou un rôle `{admin, club, recruteur, agent}` sur leur
document `users`. Un compte créé dans la console Auth n'a **aucun** document
`users` : il n'est pas exempté et disparaît en trois jours, au milieu de la
revue, le reviewer ne voyant qu'un login invalide. Passer par le portail admin
(`provisionManagedAccount`), qui écrit `createdByAdmin: true` pour tous les
rôles, `joueur` compris.

Le détail — rôle à choisir, contenu que le compte doit déjà porter, texte des
notes de revue à coller, et les deux vérifications à faire avant soumission —
est dans `docs/store-compliance.md`, section « App access ».

## 3. Fermer la migration `public_profiles` — mesuré, et moins cher qu'annoncé

La fenêtre « gratuite » était un bon réflexe appuyé sur un mauvais motif. Le
risque n'était pas de casser d'anciens clients : les règles finales sont
déployées depuis le 10 octobre, ce basculement est derrière nous. Le vrai motif
est que les tableaux de suivi hérités sont **vides aujourd'hui** et cesseront
de l'être dès les premiers suivis réels, moment où leur suppression devient une
migration de données au lieu d'un no-op.

```powershell
npm.cmd run legacy:residue:check:production
```

| Résidu | Compte | Lecture |
| --- | --- | --- |
| `users.cvUrl` encore en `http…` | **0** sur 4 comptes | rien à convertir |
| Tableaux `followersList` / `followingsList` | 4 comptes | 8 champs à supprimer |
| Arêtes de suivi dans ces tableaux | **0** | suppression sans effet observable |
| Documents `following` / `followers` | **0** | personne ne suit personne |
| `users.fcmToken` hérité | **0** | migration terminée |
| `public_profiles_and_follows_v5` | `completed` | — |
| `conversation_sort_dates_v1` | `completed` | — |
| `public_profiles_follow_cleanup_v1` | absent | nettoyage jamais lancé |

Deux vérifications ont décidé que c'était sûr, et elles comptaient plus que les
compteurs :

- **Le client actuel ne lit pas le tableau stocké.**
  `FollowController._bindFollowingStream` s'abonne à `watchFollowingIds`, qui
  lit la sous-collection `users/{uid}/following`, et **écrase**
  `user.followingsList` avec ce résultat. Le tableau Firestore n'est qu'une
  amorce de chargement et un cache optimiste.
- **La suppression de compte ne dépend pas du tableau.**
  `cleanupFollowReferences` traite les arêtes de relations en premier ; les
  tableaux ne sont qu'un filet de compatibilité explicitement commenté comme
  tel.

Conclusion : `MIRROR_LEGACY_FOLLOW_ARRAYS=false` et
`ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP=true` ne retirent rien au build 48/49.
`ENABLE_LEGACY_CV_URL_MIGRATION` reste **inactif**, pour une raison mesurée :
zéro document à convertir, et les règles finales déployées interdisent déjà
toute écriture `http` sur `cvUrl`, donc aucun flux entrant n'est possible.

La procédure exacte, le point de reprise à surveiller
(`public_profiles_follow_cleanup_v1`, et non `…_v5`) et le retour arrière sont
dans `public-profile-rollout-2026-09-28.md`, section « Procédure de fermeture ».

**État : préparé, pas déployé.** Les deux lignes ont été ajoutées à
`functions/.env.production` le 13 octobre, avec leur commentaire d'intention, et
`npm.cmd run functions:env:check:production` résout bien
`MIRROR_LEGACY_FOLLOW_ARRAYS=false` et
`ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP=true`. Il reste à lancer :

```powershell
npm.cmd run functions:deploy:production
```

Deux précautions, chacune pour une raison différente :

- `functions/.gitignore` ignore `.env.*`. L'édition **ne vit que sur ce poste**.
  Un déploiement parti d'une autre machine ne fermerait rien, et sans erreur
  visible.
- Le déploiement doit partir du shell de l'opérateur : le sandbox de
  l'assistant n'a pas de session Firebase CLI et échoue en 401 sur
  `firestore.googleapis.com`, avec un message qui accuse à tort la base
  Firestore.

## 4. La `.p8` sur `adfoot-staging` — indécidable, et non bloquant

```
user_push_tokens in adfoot-staging: 0
```

Zéro jeton ne distingue pas « la clé APNs manque » de « aucun appareil n'a
lancé de build staging ». Aucune API ne rapporte si la clé est chargée. Seul un
envoi réel sépare les deux cas, ce qui suppose un build `ios-staging` installé.

En revanche la production, elle, est prouvée — et c'est le résultat qui compte
pour le lancement :

```
Fszb…Pkr2  role=joueur  platform=ios  build=1.0.7+49
           updatedAt=2026-10-13T03:29:54Z
```

Un appareil iOS a obtenu son jeton APNs, l'a échangé contre un jeton FCM et l'a
stocké, sous le build portant le correctif `AppDelegate`. Cette preuve était
**déjà consignée** dans `messagerie-notifications-reseau-2026-10-10.md` ; elle
est ici reconfirmée en direct, ce qui n'est pas la même chose qu'un relevé
archivé. Au passage, la liste « ce qui reste à prouver » de ce document était
périmée en entier et contredisait son propre tableau de résolution : les trois
points y étaient déjà acquis. Corrigé.

Deux raccourcis npm manquaient et ont été ajoutés —
`push:ios:list:staging` et `push:ios:check:staging` — parce que
`check-ios-push-delivery.mjs` acceptait déjà `--environment staging` sans que
rien ne l'expose. Ils attendent la clé ops à l'emplacement conventionnel
`.credentials/adfoot-staging-ops.json`.

## Ce qui a été ajouté au dépôt pour obtenir ce relevé

- `scripts/check-legacy-profile-residue.mjs` — contrôle en lecture seule des
  trois préconditions de la phase 3. La checklist demandait de vérifier le
  seuil « avec des données réelles » ; rien ne le mesurait, et un opérateur
  devait s'en souvenir. Se souvenir n'est pas un contrôle.
- `package.json` — `legacy:residue:check:production`,
  `legacy:residue:gate:production` (sort en code non nul tant qu'un résidu
  subsiste, à utiliser **après** le déploiement de fermeture),
  `legacy:residue:check:staging`, `push:ios:list:staging`,
  `push:ios:check:staging`.

Aucune règle, aucun index, aucune Cloud Function n'a été déployé.

## Ordre de passage recommandé

1. **Compte de démonstration** (§2). C'est le seul élément dont l'absence
   provoque un rejet certain, et il se fait en dehors de tout déploiement.
2. **Fermeture de la migration** (§3) : `npm.cmd run functions:deploy:production`
   depuis ce poste, en release backend dédiée — rien d'autre dans le même
   déploiement — pendant que les tableaux sont encore vides. Puis attendre un
   passage horaire de `backfillPublicProfiles` et confirmer par
   `npm.cmd run legacy:residue:gate:production`.
3. **Build de soumission**, après `backend:parity:check:production` à nouveau
   vert — la parité est à revérifier *après* le déploiement de l'étape 2, pas
   avant.
4. **`.p8` staging** (§4), quand un build staging sera installé. Ne bloque pas
   le lancement.
