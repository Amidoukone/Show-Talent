# Show-Talent (mobile + backend Firebase)

## Depot lie

Ce depot porte l'application mobile Adfoot **et** le backend Firebase
partage (`firestore.rules`, `firestore.indexes.json`, `storage.rules`,
`functions/`). Le portail admin est un depot Git separe, mais consomme ce
meme backend -- ce sont deux surfaces d'un seul systeme en production.

- Ce depot (mobile + backend) : `C:\Users\konea\Desktop\ODC_PROJECT\MOBILE\Show-Talent`
- Depot admin : `C:\Users\konea\Desktop\ODC_PROJECT\WEB\Show_talent_web`
  (repo GitHub `Amidoukone/Show_talent_web`)

`scripts\check-admin-mobile-contract.ps1` detecte automatiquement le chemin
admin ci-dessus (variable `ADFOOT_ADMIN_REPO` deja definie sur cette machine
en fallback ; le defaut cable dans le script pointe aussi vers ce chemin).
Si le chemin change un jour, mettre a jour `ADFOOT_ADMIN_REPO` plutot que le
script.

## Ce depot est la source d'autorite -- le lecteur avant l'ecrivain

Ce depot deploie `firestore.rules`, `firestore.indexes.json` et les Cloud
Functions. Le portail admin ne les deploie jamais -- il les consomme.

Regle etablie apres un incident de production (le portail ecrivait `team`,
le mobile ecrivait `currentClubName`, la fiche affichait tantot l'un tantot
l'autre) : voir `docs/inter-repo-admin-mobile-runbook.md` section "Ordre de
deploiement entre les deux depots".

Ordre obligatoire, sans exception :

1. Regles Firestore + Cloud Functions (ce depot)
2. Build mobile publie et installe
3. Portail admin

## Avant toute action qui touche le contrat partage

Ne jamais modifier isolement, dans ce depot, l'un de ces elements sans vue
sur l'etat du portail admin :

- la liste des callables admin (`functions/src/index.ts`) -- doit rester
  synchronisee avec `admin/lib/utils/admin_callable_action_catalog.dart`
- les modeles de reference que l'admin recopie a l'identique :
  `lib/models/football_vocabulary.dart`, `lib/models/player_football_profile.dart`,
  `lib/models/org_football_profile.dart`, `lib/models/offre.dart`,
  `lib/utils/country_codes.dart`
- `_trustSensitiveProfileKeys` (`lib/services/users/profile_repository.dart`),
  qui doit rester le miroir exact de `ownerProfileTrustFieldsChanged()`
  (`firestore.rules`)
- tout champ ajoute a un profil footballistique -- voir la table "5
  endroits" ci-dessous
- `assertAdminCaller()` / `isAdminOperator()` (roles/claims admin)

Ajouter un fait footballistique touche ces 5 endroits, dans l'ordre :

| # | Endroit | Depot |
| --- | --- | --- |
| 1 | Le modele + `writableFieldPaths` | mobile |
| 2 | `canUpdateOwnProfile()` et `ownerProfileTrustFieldsChanged()` | mobile (`firestore.rules`) |
| 3 | `_trustSensitiveProfileKeys` | mobile (`profile_repository.dart`) |
| 4 | Le validateur du callable | mobile (`functions/src/`) |
| 5 | Le miroir du modele, regenere | admin |

Verifier avec (depuis ce depot) :

```powershell
.\scripts\check-admin-mobile-contract.ps1
```

ou depuis le depot admin :

```powershell
npm.cmd run contract:mobile
```

## Docs de reference

Ici (generalement la version la plus a jour en cas de divergence) :
- `docs/inter-repo-admin-mobile-runbook.md`
- `docs/shared-backend-contract.md`

Cote admin (a comparer en cas de doute) :
- `docs/prd-runbook-exploitation-inter-depots.md`
- `docs/runbook-production-admin-mobile.md`
