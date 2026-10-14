# Documents juridiques Adfoot, registre de publication

Les CGU et la politique de confidentialité sont rédigées comme un socle unique
pour tous les pays où Adfoot propose le service. Il n'y a pas de variante de
texte par pays. Les protections impératives applicables à la situation d'une
personne prévalent si elles lui donnent davantage de droits.

## État : publié le 14 octobre 2026, version 1.0

Les brouillons que ce dossier contenait ont été validés et publiés. **Les
fichiers de référence sont désormais dans `site_pub/legal/`**, et ce dossier ne
contient plus de copie de travail, et c'est volontaire : deux textes juridiques
divergents dans un même dépôt finissent par être recopiés dans le mauvais sens.
L'ancienne procédure de ce fichier demandait précisément « copier les documents
validés vers `site_pub/legal/` », ce qui, appliqué après publication, aurait
écrasé le texte publié par un brouillon périmé. Les brouillons restent
consultables dans l'historique git (commit précédant le 14 octobre 2026).

| Fichier publié | Rôle |
| --- | --- |
| `site_pub/legal/terms.html` | CGU, version de référence (français) |
| `site_pub/legal/terms.en.html` | Traduction anglaise des CGU |
| `site_pub/legal/privacy-policy.html` | Politique de confidentialité, version de référence |
| `site_pub/legal/privacy-policy.en.html` | Traduction anglaise de la politique |
| `site_pub/legal/account-deletion.html` | Procédure de suppression (URL déclarée aux stores) |
| `site_pub/legal/account-deletion.en.html` | Traduction anglaise de la procédure |
| `site_pub/legal/styles.css` | Feuille de style commune aux six pages |

Le français est la version de référence et le `x-default` ; chaque page porte
ses balises `rel="alternate" hreflang`. Les deux textes le disent explicitement :
en cas de divergence, le français prévaut.

## Ce qui a été tranché le 14 octobre 2026

- **Version et date d'effet :** version 1.0, en vigueur le 14 octobre 2026.
- **Adresses de contact :** deux boîtes, avec des rôles distincts.
  `support@adfoot.org` reçoit les demandes de compte, les signalements, la
  sécurité, et l'accord parental et l'autorisation média d'un joueur mineur.
  `contact@adfoot.org` est le contact de l'éditeur SIRA SARL et reçoit les
  demandes relatives aux données personnelles. Les deux sont des alias
  `@adfoot.org` redirigés par ImprovMX : **les deux doivent exister et être
  relevées**. La répartition exacte est reprise dans
  `../store-compliance.md`.
- **Durées de conservation :** inscrites dans la politique sous forme de
  tableau, avec les valeurs effectivement appliquées par le code :
  `CLIENT_LOG_RETENTION_DAYS = 90` et `TELEMETRY_LOG_RETENTION_DAYS = 30`
  (`functions/src/actions.ts`), `UNVERIFIED_ACCOUNT_RETENTION_DAYS` par défaut
  à 3 jours avec `UNVERIFIED_PURGE_EXCLUDE_MANAGED = true`
  (`functions/src/cleanup.ts`). Modifier l'une de ces constantes rend la
  politique fausse : la mettre à jour en même temps.
- **Prestataires et transferts :** Google Firebase / Google Cloud (fonctions
  serveur en `europe-west1`), Brevo pour l'envoi des courriels, ImprovMX pour
  leur réception. Les trois sont nommés dans la politique.

## Reste à faire

- **Préciser la région de la base de données et du stockage.** Seule la région
  des Cloud Functions (`europe-west1`) est documentée dans le dépôt. La
  politique dit aujourd'hui que la base, les fichiers et les sauvegardes sont
  « hébergés sur cette même infrastructure Google Cloud », ce qui est exact
  sans être précis. Relever `locationId` du projet `adfoot-production` et, si
  la région diffère, l'inscrire dans la section 5 des deux politiques.
- **Revue par un conseil** connaissant l'activité, l'usage d'images de joueurs,
  les utilisateurs mineurs et les marchés de lancement. Le texte reste commun ;
  cette revue vérifie les règles impératives sans créer de versions nationales.
- **Déclarations Google Play Families.** L'âge minimum est 12 ans, donc
  l'audience déclarée comprend des moins de 13 ans. Les
  [règles Families](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en)
  demandent notamment une action adulte avant certaines fonctions sociales
  permettant l'échange de données personnelles, et un moyen pour l'adulte de
  gérer ces fonctions. L'acceptation des CGU par le mineur et l'enregistrement
  oral par l'admin ne suffisent pas à eux seuls. Apple impose en parallèle ses
  exigences de modération du contenu créé par les utilisateurs
  ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
- **Accès par lien public aux vidéos de mineurs.** Le candidat refuse les
  vidéos mineures sur la page anonyme `/v/...`, même après accord média. Ce
  contrôle ne révoque pas les URL de téléchargement déjà copiées : les jetons
  Storage et les copies hors application restent à prendre en compte avant de
  promettre une restriction absolue des médias aux recruteurs vérifiés. La
  politique est rédigée en conséquence (section 4, dernier paragraphe) et ne
  promet pas l'impossible.
- **Armer la porte d'acceptation.** `TermsConfig.bundledVersion` reste vide :
  la porte est dormante jusqu'à l'écriture de `config/legal`. Procédure et
  ordre des étapes dans `../store-compliance.md`, section « Activating the
  acceptance gate ». Ne pas l'armer avant d'avoir ouvert les URL publiées.

## Parcours mineur décrit par les textes

- L'administration crée le compte et le titulaire accepte les CGU dans
  l'application comme tout autre titulaire.
- L'administration enregistre séparément l'accord du parent/tuteur, oral ou
  écrit, avec les éléments de traçabilité disponibles. Aucune signature
  manuscrite dans le portail n'est requise.
- Sans accord parental consigné, la projection publique du profil reste
  masquée et l'ajout de médias est bloqué.
- Après accord, la fiche mineur est une projection limitée, accessible aux
  recruteurs vérifiés. Les demandes de contact sont médiées et la messagerie
  directe est désactivée.
- L'usage de photos/vidéos nécessite une autorisation média distincte ; la
  publication des vidéos passe par la modération admin. L'usage d'images dans
  les campagnes Adfoot ou les captures de stores demande une autorisation
  promotionnelle distincte.
- Le parent ou tuteur peut demander à tout moment l'activation, la
  désactivation ou le retrait de l'accord parental et de l'autorisation média
  en écrivant à `support@adfoot.org`, sans avoir de compte Adfoot.
  `withdrawManagedMinorConsent` retire la projection publique et purge les
  médias publiés après une demande parentale vérifiée.
- L'identité du compte admin créateur et la date de création sont conservées
  pour l'audit interne.

## Modifier un texte publié

1. Modifier la page française **et** sa traduction anglaise ensemble.
2. Si le changement est substantiel, monter la version (`1.1`, …) et la date
   d'effet dans les quatre pages concernées, puis dans `config/legal` : les
   comptes revoient alors l'écran d'acceptation. Un changement rédactionnel
   mineur ne doit pas monter la version, sous peine de redemander son accord à
   toute la base pour une virgule.
3. `flutter test test/terms_acceptance_guardrails_test.dart` : vérifie que
   chaque URL émise par l'app ou par le courriel d'invitation correspond à un
   fichier existant, et qu'aucune page publiée ne porte de marqueur de
   brouillon.
4. Déployer l'hébergement, puis `node scripts/check-production-hosting.mjs`
   pour comparer les octets déployés aux fichiers du dépôt.
