# Brouillons juridiques — CGU et politique de confidentialité

Ces deux documents ne sont **pas publiés**. Ils vivent hors de `site_pub/`
précisément pour qu'aucun `firebase deploy --only hosting` ne puisse les mettre
en ligne par inadvertance : la page de confidentialité réellement servie est
`site_pub/legal/privacy-policy.html`, et c'est l'URL déclarée au Play Console.

| Fichier | Remplace / crée | État |
| --- | --- | --- |
| `terms.html` | crée `/legal/terms.html` — n'existe pas encore en ligne | brouillon |
| `privacy-policy.html` | remplace `/legal/privacy-policy.html` | brouillon |

`styles.css` est une copie de `site_pub/legal/styles.css`, uniquement pour
pouvoir ouvrir les brouillons dans un navigateur avec le bon rendu.

## Structure retenue

L'éditeur et responsable du traitement est **Adfoot** (Amidou Digital
Football), **structure autonome** à créer au Mali. Adfoot n'est ni une filiale
ni un nom commercial d'une autre entité : elle répond seule de ses engagements
et de ses traitements de données.

Ce choix a une conséquence directe et favorable pour ces documents : il n'y a
aucun groupe, donc aucune question de partage de données entre sociétés
soeurs — ce qu'un club européen ou un DPO demande systématiquement dès qu'il
voit une holding. La politique de confidentialité peut l'affirmer sans réserve.

Un point reste à traiter, indépendamment de la structure : **déposer la marque
« Adfoot » à l'OAPI**, pas pays par pays. Un seul dépôt couvre les 17 États
membres, dont le Mali. À faire avant toute communication publique, sous peine
d'avoir à racheter son propre nom.

## Le blocage n°1 : Adfoot n'est pas encore immatriculée

Les deux documents portent un marqueur explicite à ce sujet. Publier une
politique de confidentialité qui désigne comme responsable du traitement une
société inexistante laisserait les utilisateurs sans interlocuteur juridiquement
identifiable — ce que l'article 13 du RGPD interdit.

Deux options, à trancher :

1. **Attendre l'immatriculation d'Adfoot**, puis remplir RCCM, forme, capital,
   siège, et publier. C'est le chemin propre.
2. **Publier maintenant au nom de la personne physique** qui exploite le
   service, puis republier au nom de la société une fois créée. Cela permet d'ouvrir
   au public plus tôt, au prix d'une responsabilité personnelle dans
   l'intervalle et d'une seconde publication.

## Une incohérence de positionnement à surveiller

Adfoot se présente comme « une agence de football ». L'article 9 des CGU
distingue désormais explicitement deux métiers : la **promotion et
l'accompagnement**, que vous exercez, et l'activité **réglementée d'agent de
football**, que vous n'exercez pas — pas de mandat, pas de commission sur un
contrat ou un transfert.

Cette phrase est ce qui vous garde hors du périmètre du Règlement FIFA sur les
Agents de Football et de ses obligations de licence. Le jour où Adfoot prendrait
un pourcentage sur un contrat de joueur, le régime change entièrement et ces
documents devraient être refaits.

## Ce qu'il reste à faire

1. Compléter les passages surlignés (`class="todo"`) : forme juridique, capital,
   RCCM et siège d'Adfoot, directeur de publication, téléphone, date d'entrée en
   vigueur, référence exacte de la loi malienne sur les données et nom de son
   autorité de contrôle, représentant dans l'Union européenne (art. 27 RGPD),
   durée de conservation de la preuve d'acceptation, mécanisme de transfert
   hors UE.
2. Faire valider l'ensemble par un conseil admis à exercer au Mali.
3. Retirer le bandeau `.draft-banner` et le bloc `<style>` qui porte les
   marqueurs, en haut de chaque fichier.
4. Copier les deux fichiers dans `site_pub/legal/`, puis
   `firebase deploy --only hosting --project production`.
5. Ajouter les liens dans le pied de page de `site_pub/index.html` et dans
   `site_pub/sitemap.xml`.
6. Écrire `config/legal` dans Firestore pour activer la porte d'acceptation
   dans l'application :

   ```json
   {
     "requiredVersion": "1.0",
     "termsUrl": "https://adfoot.org/legal/terms.html",
     "privacyUrl": "https://adfoot.org/legal/privacy-policy.html",
     "effectiveOn": "1 septembre 2026"
   }
   ```

   Tant que ce document n'existe pas, la porte reste dormante et personne n'est
   invité à accepter un texte inexistant — voir
   `lib/services/legal/terms_acceptance_service.dart`.

## Deux points à trancher avant publication

- **Les deux vidéos `#U17`** publiées et approuvées en production contredisent
  la règle des 18 ans retenue à l'article 4 des CGU. Soit elles partent, soit
  l'âge minimum change.
- **Le réglage « visibilité du profil »** masque la page de profil et le CV,
  mais ne rend pas la fiche invisible au niveau des règles Firestore. La
  politique de confidentialité le signale (section 4.1) : soit la restriction
  est renforcée côté serveur, soit la limite est décrite honnêtement.
