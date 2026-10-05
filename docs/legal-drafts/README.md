# Documents juridiques communs Adfoot

Les CGU et la politique de confidentialité sont rédigées comme un socle unique
pour tous les pays où Adfoot propose le service. Il n’y a pas de variante de
texte par pays. Les protections impératives applicables à la situation d’une
personne prévalent si elles lui donnent davantage de droits.

## Fichiers et état

| Fichier | Rôle | État |
| --- | --- | --- |
| `terms.html` | CGU communes, y compris joueurs, clubs, recruteurs, agents, supporters et mineurs | Brouillon à valider |
| `privacy-policy.html` | Politique commune décrivant les données, usages, accès, prestataires et droits | Brouillon à valider |
| `../../site_pub/legal/terms.draft.html` | Copie de travail destinée à devenir `/legal/terms.html` après validation | Ignorée par Firebase Hosting (`**/*.draft.html`) |
| `../../site_pub/legal/privacy-policy.draft.html` | Copie de travail destinée à remplacer la politique publiée | Ignorée par Firebase Hosting (`**/*.draft.html`) |
| `../../site_pub/legal/privacy-policy.html` | Politique actuellement publiée | Inchangée jusqu’à validation et publication explicite |

Les brouillons ne sont pas activés par l’application et ne sont pas accessibles
aux URL canoniques d’acceptation. `TermsConfig.bundledVersion` reste vide et la
porte d’acceptation reste donc inactive. Cette séparation évite de demander aux
utilisateurs d’accepter un texte qui n’est pas encore accessible, validé et
publié.

## Parcours mineur décrit

- L’administration crée le compte et le titulaire accepte les CGU dans
  l’application comme tout autre titulaire.
- L’administration enregistre séparément l’accord du parent/tuteur, oral ou
  écrit, avec les éléments de traçabilité disponibles. Aucune signature
  manuscrite dans le portail n’est requise.
- Sans accord parental consigné, la projection publique du profil reste
  masquée et l’ajout de médias est bloqué.
- Après accord, la fiche mineur est une projection limitée, accessible aux
  recruteurs vérifiés. Les demandes de contact sont médiées et la messagerie
  directe est désactivée.
- L’usage de photos/vidéos nécessite une autorisation média distincte ; la
  publication des vidéos passe par la modération admin. L’usage d’images dans
  les campagnes Adfoot ou les captures de stores demande une autorisation
  promotionnelle distincte.
- L’identité du compte admin créateur et la date de création sont conservées
  pour l’audit interne.

**Contrôle technique ajouté le 4 octobre 2026 :** le candidat refuse les vidéos
mineures sur la page anonyme `/v/...`, même après accord média. Ce contrôle
doit être déployé avec les audiences vidéo calculées côté serveur. Il ne
révoque pas les URL de téléchargement déjà copiées : les jetons Storage et
les copies hors application restent à prendre en compte avant de promettre
une restriction absolue des médias aux recruteurs vérifiés.

## Informations nécessaires avant publication

1. Identit&eacute; confirm&eacute;e : SIRA DIGITAL INNOVATION STUDIO SARL, en abr&eacute;g&eacute; SIRA SARL, immatricul&eacute;e au Mali sous le num&eacute;ro 425900104010012M0004L ; si&egrave;ge &agrave; Bamako, Quartier S&eacute;b&eacute;nikoro, pr&egrave;s de la station ORYX ; t&eacute;l&eacute;phone 70.45.33.45. Contact : support@adfoot.org.
2. Fixer et inscrire la version et la date d’effet communes.
3. Confirmer les régions effectives de Firestore et Cloud Storage, le contrat
   Firebase/Google Cloud et les garanties de transfert international ; confirmer
   aussi les modalités de traitement des courriels par Brevo.
4. Fixer les durées opérationnelles de conservation (comptes, journaux,
   demandes, acceptation, accord parental, médias supprimés et sauvegardes) et
   s’assurer qu’elles correspondent au code et aux outils d’administration.
5. Faire relire les deux documents par un conseil connaissant l’activité,
   l’usage d’images de joueurs, les utilisateurs mineurs et les marchés de
   lancement. Le texte reste commun ; cette revue vérifie les règles
   impératives sans créer des versions nationales séparées.
6. Vérifier séparément les déclarations d’audience et les règles des stores au
   regard des fonctions réelles. Si l’audience déclarée de Google Play comprend
   des enfants, ses [règles Families](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en)
   demandent notamment une action adulte avant certaines fonctions sociales
   qui leur permettent d’échanger des données personnelles, ainsi qu’un moyen
   pour l’adulte de gérer ces fonctions. Apple impose ses exigences de
   modération du contenu créé par les utilisateurs dans ses
   [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
   Ne pas supposer que la simple acceptation des CGU par le mineur ou
   l’enregistrement oral par l’admin satisfait à lui seul les critères de
   chaque store.
7. Contact et gestion parentale confirm&eacute;s : support@adfoot.org re&ccedil;oit les demandes d'acc&egrave;s, de rectification et de suppression, ainsi que les demandes parentales de modification ou de retrait des autorisations. Le parent n'a pas besoin de compte dans l'application.

## D&eacute;cisions confirm&eacute;es le 3 octobre 2026

- &Acirc;ge minimum : 12 ans ; lancement au Mali. Les joueurs de 12 &agrave; 17 ans n&eacute;cessitent un accord parental consign&eacute; oralement ou par &eacute;crit par l'administration.
- La cible comprend donc des moins de 13 ans ; valider les exigences Google Play Families de gestion adulte des fonctions sociales avant soumission.
- Les brouillons contiennent les coordonn&eacute;es confirm&eacute;es, mais restent non publi&eacute;s. Restent &agrave; r&eacute;gler : acc&egrave;s par lien public aux vid&eacute;os de mineurs, dur&eacute;es de conservation, prestataires/transferts de donn&eacute;es, revue juridique et dates/version d'effet.

## Publication contrôlée

Après résolution des éléments précédents :

1. Copier les deux documents validés vers `site_pub/legal/terms.html` et
   `site_pub/legal/privacy-policy.html`, retirer les bannières de brouillon et
   mettre à jour la date/version. Ne pas publier les fichiers `.draft.html`.
2. Vérifier les liens des invitations, des boutiques, du pied de page et de la
   page de suppression ; ajouter CGU au pied de page et au sitemap.
3. Ouvrir les deux URL publiques sur téléphone et ordinateur, puis vérifier
   les liens et le rendu avant activation de l’application.
4. Déployer le site par le processus de release approuvé. Aucun déploiement
   n’est effectué par cette préparation locale.
5. Écrire ensuite `config/legal` dans le projet Firebase approprié, par exemple
   avec `requiredVersion: "1.0"`, les deux URL canoniques et la date d’effet.
   Faire cette activation après vérification des pages publiques : elle impose
   la nouvelle acceptation à tous les comptes concernés.
6. Contrôler le parcours d’acceptation sur Android et iOS en staging, y compris
   utilisateur existant, nouvelle version, liens hors connexion, retour depuis
   le navigateur, refus et suppression de compte. Promouvoir ensuite selon le
   processus habituel.

Ne pas renseigner `config/legal.requiredVersion` tant que les pages canoniques
ne sont pas publiées et consultables. Ne pas déployer les règles Firebase ou
les fonctions pour ce seul changement de rédaction.
