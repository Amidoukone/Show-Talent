# Publication des documents juridiques, 14 octobre 2026

Les conditions d'utilisation renvoyaient une erreur 404. Ce relevé décrit ce
qui a été mesuré, ce qui a été corrigé dans le dépôt, et les trois actions
humaines qui restent avant la soumission finale.

Aucun déploiement n'a été fait par cette préparation. `functions/src/` n'est pas
touché : **aucun déploiement de Cloud Functions n'est nécessaire** pour ce
correctif.

## Le défaut, mesuré

```
404  https://adfoot.org/legal/terms.html
200  https://adfoot.org/legal/privacy-policy.html
200  https://adfoot.org/legal/account-deletion.html
```

`site_pub/legal/terms.html` n'existait pas. Seul `terms.draft.html` existait, et
`firebase.json` ignore `**/*.draft.html` : le brouillon n'était donc pas servi
non plus.

Deux surfaces visibles par les utilisateurs, pas une :

| Surface | Code | Effet dans le build 48 |
| --- | --- | --- |
| Courriel d'activation de compte | `functions/src/email_delivery.ts:78` (`TERMS_URL`) | le lien « Conditions d'utilisation » ouvre un 404 |
| Réglages ▸ Documents ▸ Conditions | `lib/screens/setting_screen.dart` (`termsUrl`) | la tuile ouvre le même 404 |

Et la porte d'acceptation (`TermsAcceptanceScreen`) pointait sur la même URL :
une fois armée, elle aurait demandé à chaque utilisateur d'accepter un texte
illisible.

### Pourquoi rien ne l'a attrapé

Trois contrôles existaient et aucun ne couvrait cette page.

- `scripts/check-android-release-readiness.ps1` ne vérifiait que
  `privacy-policy.html` et `account-deletion.html`.
- `scripts/check-production-hosting.mjs` comparait les mêmes deux pages, et
  **affirmait** que `/legal/terms.draft.html` renvoie 404, ce qui était vrai,
  et sans rapport avec la page réellement liée.
- `scripts/smoke-release-candidate.mjs` demandait `privacy-policy.html` et le
  404 du brouillon.

Le fait que les CGU manquaient était consigné dans
`docs/legal-drafts/README.md` comme un travail en cours, mais le relevé de
lancement du 13 octobre ne le listait pas parmi les décisions ouvertes.

### Une seconde incohérence, trouvée au passage

L'adresse de contact divergeait selon le fichier :

| Emplacement | Adresse |
| --- | --- |
| app (`app_fr.arb`, `app_en.arb`), `docs/store-compliance.md`, brouillons `docs/legal-drafts/` | `support@adfoot.org` |
| site public (`index.html`, `account-deletion.html`, brouillons `site_pub/legal/`) | `contact@adfoot.org` |

Les deux copies du même brouillon ne différaient **que** par cette adresse.

## Ce qui a été publié

Version **1.0**, en vigueur le **14 octobre 2026**, en français et en anglais.
Le français est la version de référence et le `x-default` ; les deux textes le
disent explicitement.

| Fichier | État |
| --- | --- |
| `site_pub/legal/terms.html` | nouveau, comble le 404 |
| `site_pub/legal/terms.en.html` | nouveau |
| `site_pub/legal/privacy-policy.html` | remplace la version courte intérimaire |
| `site_pub/legal/privacy-policy.en.html` | nouveau |
| `site_pub/legal/account-deletion.html` | adresses alignées, section mineurs et conservation ajoutées |
| `site_pub/legal/account-deletion.en.html` | nouveau |

Les quatre brouillons (`site_pub/legal/*.draft.html` et
`docs/legal-drafts/*.html`) ont été retirés. Motif : la procédure inscrite dans
`docs/legal-drafts/README.md` demandait de « copier les documents validés vers
`site_pub/legal/` », ce qui, appliqué après publication, aurait écrasé le texte
publié par un brouillon périmé : adresses, version et durées incluses. Le README
est devenu le registre de publication. Les brouillons restent dans l'historique
git.

### Les deux trous du brouillon, comblés avec des valeurs mesurées

Le brouillon portait deux `<span class="pending">`. Ils sont remplis avec ce que
le code applique réellement, pas avec des durées plausibles.

| Donnée | Durée publiée | Source |
| --- | --- | --- |
| Journaux d'erreurs et journaux d'action vidéo | 90 jours | `CLIENT_LOG_RETENTION_DAYS` (`functions/src/actions.ts:367`) |
| Autres journaux de diagnostic et télémétrie | 30 jours | `TELEMETRY_LOG_RETENTION_DAYS` (`functions/src/actions.ts:368`) |
| Compte non vérifié et non créé par l'administration | 3 jours | `UNVERIFIED_ACCOUNT_RETENTION_DAYS`, défaut `DEFAULT_RETENTION_DAYS = 3` (`functions/src/cleanup.ts:13`) |

La formulation du troisième point est précise à dessein :
`UNVERIFIED_PURGE_EXCLUDE_MANAGED` vaut `true` par défaut et
`provisionManagedAccount` écrit `createdByAdmin: true` pour tous les rôles, donc
les comptes réels **ne sont pas** purgés. Écrire « tout compte non vérifié est
supprimé en 3 jours » aurait été faux.

Prestataires nommés : Google Firebase / Google Cloud (fonctions serveur en
`europe-west1`), Brevo pour l'envoi des courriels, ImprovMX pour leur réception.
ImprovMX traite donc les messages que les utilisateurs nous envoient, et ne
figurait dans aucune version précédente.

### Les deux adresses, avec des rôles distincts

- `support@adfoot.org` : compte et accès, signalements, sécurité, accord
  parental et autorisation média d'un joueur mineur.
- `contact@adfoot.org` : contact de l'éditeur SIRA SARL et demandes relatives
  aux données personnelles.

Cette répartition a été choisie parce qu'elle ne contredit aucune chaîne
existante : toutes les mentions dans l'app restent justes, et le site public
reste juste. La table complète est dans `docs/store-compliance.md`.

## Ce qui empêche la récidive

Quatre contrôles, et chacun a été vérifié en négatif, c'est-à-dire en
reproduisant la panne pour voir le contrôle échouer.

| Contrôle | Ce qu'il refuse | Vérifié en négatif |
| --- | --- | --- |
| `test/terms_acceptance_guardrails_test.dart` | une URL de `TermsConfig` ou du courriel d'invitation sans fichier correspondant sous `site_pub/legal/` | page retirée → 2 tests en échec, message nommant le fichier manquant |
| idem | une page publiée portant encore `class="draft"`, `class="pending"` ou « à confirmer » | déclenché par la page retirée |
| `scripts/check-android-release-readiness.ps1` | `terms.html` ou `legal/styles.css` absent, marqueur de brouillon, URL des CGU absente de `store-compliance.md` | page retirée → gate en code 1, `Missing store/compliance file` |
| `scripts/check-production-hosting.mjs` | les 6 pages et leur feuille de style, comparées octet à octet au dépôt | 11 fichiers listés, 0 manquant |

`scripts/smoke-release-candidate.mjs` demande en plus 200 sur `terms.html`,
`terms.en.html` et `privacy-policy.en.html`, et conserve le 404 du brouillon
comme refus permanent.

Le contrôle qui manquait est le premier : il relie les URL que le code émet aux
fichiers que l'hébergement sert. C'est le seul qui aurait vu ce défaut, parce
que c'est le seul qui part du code plutôt que d'une liste écrite à la main.

## La porte d'acceptation reste dormante, volontairement

`TermsConfig.bundledVersion` reste la chaîne vide. Écrire `'1.0'` ici armerait
la porte dès le prochain build, **même si le déploiement de l'hébergement
n'avait pas eu lieu**, ce qui recréerait exactement le 404 que ce correctif
ferme. L'activation passe par `config/legal`, après vérification des URL en
ligne. Procédure dans `docs/store-compliance.md`, section « Activating the
acceptance gate ».

L'app route désormais vers la page anglaise quand la langue active est
l'anglais (`TermsConfig.termsUrlForLanguage`, appelé depuis les deux écrans qui
ouvrent ces liens). Ce routage demande un nouveau build, mais il se dégrade
proprement : un build déjà installé ouvre la page française, qui fonctionne.

## Vérifications passées

- `flutter test` : **1041/1041**. La suite comptait un échec **préexistant**,
  sans lien avec ce travail : `scripts/check-legacy-profile-residue.mjs` codait
  en dur `.credentials/adfoot-production-ops.json` dans un exemple d'usage, ce
  que `test/sign_in_never_hangs_guardrails_test.dart` refuse. Confirmé
  préexistant en remisant les modifications, puis corrigé.
- `flutter analyze` sur tout le projet : aucun problème.
- `npm.cmd run quality:coherence:check` : vert.
- `npm.cmd run release:android:check` (gate complet) : vert.
- `npm.cmd run contract:admin-mobile:check` : vert.
- Les 6 pages : structure, balises appariées, liens relatifs et absolus
  `/legal/` tous résolus, aucune adresse e-mail hors des deux retenues, aucun
  marqueur de brouillon. Sitemap : 8 URL, toutes servies par un fichier
  existant.

## Reste à faire : trois actions humaines

1. **Vérifier que les deux alias existent dans ImprovMX et sont relevés.**
   C'est le seul point que le dépôt ne peut pas prouver : les MX sont
   `mx1/mx2.improvmx.com` (voir `AUTH_EMAIL_DELIVERABILITY_RUNBOOK.md`), et une
   page juridique qui nomme une boîte que personne n'ouvre est une promesse non
   tenue. À faire **avant** le déploiement de l'hébergement.
2. **Déployer l'hébergement**, puis vérifier :

   ```powershell
   npm.cmd run hosting:marketing:deploy:production
   node scripts/check-production-hosting.mjs
   ```

   Puis ouvrir `/legal/terms.html` et `/legal/terms.en.html` sur téléphone et
   sur ordinateur, et suivre le sélecteur de langue dans les deux sens.
3. **Armer la porte** en écrivant `config/legal` dans `adfoot-production`, et
   accepter les conditions une fois sur le compte de démonstration App Review,
   sinon le relecteur rencontre l'écran de consentement en premier.

Reste ouvert et indépendant de ce travail : préciser la région de la base et du
stockage dans la section 5 des deux politiques (seule la région des Cloud
Functions est documentée dans le dépôt), la revue par un conseil, et les
déclarations Google Play Families liées à l'âge minimum de 12 ans. Détail dans
`docs/legal-drafts/README.md`, section « Reste à faire ».
