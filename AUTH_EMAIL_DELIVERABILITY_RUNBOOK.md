# Délivrabilité des e-mails d'authentification

Pourquoi le lien « mot de passe oublié » arrive en spam, la procédure pour
qu'il arrive en boîte de réception, et comment l'invitation part maintenant
toute seule à la création d'un compte.

## Les deux e-mails, et qui les envoie

| E-mail | Déclenché par | Expédié par | Ce qu'il faut faire |
| --- | --- | --- | --- |
| Réinitialisation du mot de passe | l'utilisateur, écran de connexion | Firebase Authentication | **Étapes 1 à 5** : déclarer le SMTP Brevo dans la console. Aucun code. |
| Vérification d'adresse | l'application | Firebase Authentication | idem, même écran de configuration. |
| Invitation à la création d'un compte | l'admin, portail web | **nos Cloud Functions** | **Étape 6** : un secret et un redéploiement. |

La distinction est la clé de tout le document. Pour les deux premiers, aucune
ligne de Dart ne peut résoudre le spam : Firebase compose et expédie
lui-même, tout se joue dans la console Brevo, chez le registrar DNS de
`adfoot.org` et dans la console Firebase. Le troisième, lui, n'existait pas du
tout : la Function fabriquait un lien et le rendait à l'admin, qui le
copiait-collait à la main.

## Le diagnostic (spam)

Les deux e-mails que Firebase envoie — vérification d'adresse et
réinitialisation de mot de passe — sont composés et expédiés par son serveur
d'envoi intégré, pas par nous :

| Ce qui envoie | Adresse d'expéditeur | Authentifié pour `adfoot.org` ? |
| --- | --- | --- |
| Firebase Auth (défaut, aujourd'hui) | `noreply@adfoot-production.firebaseapp.com` | non |
| Brevo (cible) | `no-reply@adfoot.org` | oui, via SPF + DKIM + DMARC |

Un filtre anti-spam évalue l'alignement entre le domaine affiché et le domaine
qui signe le message. Aujourd'hui il n'y en a aucun : le message se présente au
nom d'Adfoot mais est signé par `firebaseapp.com`, domaine mutualisé entre tous
les projets Firebase du monde et porteur de la réputation d'envoi de tout le
monde sauf de la nôtre. Gmail et Outlook classent régulièrement ces messages en
indésirables. Rien dans le contenu du message n'y change quoi que ce soit.

Palliatif déjà en place côté application : l'écran de connexion nomme
explicitement le dossier spam dans sa confirmation d'envoi
(`lib/screens/login_screen.dart`). C'est un pansement, pas une solution.

## Coût

**Zéro euro.** L'offre gratuite de Brevo couvre 300 e-mails par jour, sans carte
bancaire. Le projet compte 17 comptes ; le volume réel est de quelques dizaines
de messages par mois. Le plafond ne sera pas approché.

Le coût réel est en temps : environ une heure de configuration, plus quelques
heures de propagation DNS avant de pouvoir vérifier.

## Risque, et comment revenir en arrière

Le risque n'est pas que les e-mails continuent d'arriver en spam : c'est qu'un
SMTP mal renseigné les empêche de partir du tout. Deux précautions :

1. Tester sur vos propres adresses avant d'en parler aux testeurs.
2. En cas de problème, **vider les champs SMTP dans Firebase** : la console
   reprend immédiatement l'expéditeur par défaut. Le retour arrière prend trente
   secondes et ne demande aucun déploiement.

**Aucune version à publier sur la Play Console.** Les étapes 1 à 5 ne touchent
qu'à des consoles. L'étape 6 redéploie deux Cloud Functions — et uniquement
celles-là, jamais l'application mobile.

---

## Étape 1 — Compte Brevo

1. Créer un compte sur `brevo.com` (offre gratuite, aucune carte demandée).
2. Menu **Senders, Domains & Dedicated IPs** → onglet **Domains** → **Add a
   domain** → saisir `adfoot.org`.
3. Brevo affiche alors les enregistrements DNS à publier. **Garder cet écran
   ouvert** : les valeurs DKIM sont propres à votre compte, personne d'autre ne
   peut vous les donner.

## Étape 2 — DNS de `adfoot.org`

Chez le registrar du domaine. Trois enregistrements :

Le domaine est chez **Squarespace**. Dans le champ *Host*, ne jamais taper
`adfoot.org` : `@` pour la racine, et seulement la partie gauche pour le reste
(`_dmarc`, `brevo._domainkey`). Squarespace ajoute le domaine lui-même. Ne pas
entourer les valeurs de guillemets.

### État constaté le 2026-08-26 (avant toute modification)

| | Valeur |
| --- | --- |
| MX | `mx1.improvmx.com` / `mx2.improvmx.com` |
| SPF | `v=spf1 include:spf.improvmx.com ~all` |
| DKIM | aucun |
| DMARC | aucun |
| autre TXT | `hosting-site=adfoot-production` (vérification Firebase Hosting) |

**Il existe donc déjà un SPF**, posé pour ImprovMX qui redirige les adresses
`@adfoot.org`. C'est le piège central de cette étape.

### Ce qu'il faut faire

| Action | Type | Host | Valeur |
| --- | --- | --- | --- |
| **Modifier l'existant** | TXT | `@` | `v=spf1 include:spf.improvmx.com include:spf.brevo.com ~all` |
| Ajouter | TXT | `@` | le `brevo-code…` affiché par Brevo (preuve de propriété) |
| Ajouter | TXT | le sélecteur affiché par Brevo, ex. `brevo._domainkey` | la clé DKIM affichée par Brevo |
| Ajouter | TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@adfoot.org` |

Trois pièges :

- **Un seul enregistrement SPF par domaine.** Créer un second SPF pour Brevo
  invaliderait les deux — et casserait la redirection ImprovMX au passage. On
  ajoute `include:spf.brevo.com` **dans** la ligne existante : un seul
  `v=spf1`, un seul `~all`, les deux `include` au milieu.
- Le nom exact du sélecteur DKIM est celui qu'affiche Brevo, pas celui de ce
  tableau.
- Ne toucher ni aux MX ImprovMX, ni au TXT `hosting-site=adfoot-production`.

Adresse dans `rua=` : une boîte réellement relevée — donc créer l'alias
`dmarc@` dans ImprovMX, ou mettre une adresse qui fonctionne déjà. Sinon les
rapports DMARC se perdent.

### Vérifier soi-même avant de continuer

```powershell
Resolve-DnsName adfoot.org -Type TXT -Server 8.8.8.8 | Select-Object -ExpandProperty Strings
Resolve-DnsName brevo._domainkey.adfoot.org -Type TXT -Server 8.8.8.8 | Select-Object -ExpandProperty Strings
Resolve-DnsName _dmarc.adfoot.org -Type TXT -Server 8.8.8.8 | Select-Object -ExpandProperty Strings
```

Un seul `v=spf1` doit apparaître, contenant les deux `include`. Deux lignes
`v=spf1` = corriger avant d'aller plus loin.

**ImprovMX et Brevo ne se gênent pas.** ImprovMX tient les MX, c'est-à-dire la
*réception* ; Brevo ne touche qu'à l'*envoi*. Le seul enregistrement partagé
est le SPF, d'où la fusion ci-dessus.

Attendre la validation dans Brevo (quelques minutes à quelques heures) avant de
passer à la suite.

## Étape 3 — Identifiants SMTP Brevo

Dans Brevo : **SMTP & API** → onglet **SMTP**. Noter :

- serveur : `smtp-relay.brevo.com`
- port : `587`
- login : l'adresse du compte Brevo
- mot de passe : la **clé SMTP** générée là (ce n'est pas le mot de passe du
  compte Brevo)

## Étape 4 — Déclarer le SMTP dans Firebase

Console Firebase → projet **adfoot-production** → **Authentication** →
onglet **Templates** → icône crayon → **Paramètres SMTP** :

Le formulaire réellement affiché ne contient que six champs — ni nom
d'expéditeur, ni adresse de réponse :

| Champ (libellé exact) | Valeur |
| --- | --- |
| Sender address | `no-reply@adfoot.org` |
| SMTP server host | `smtp-relay.brevo.com` |
| SMTP server port | `587` |
| SMTP account username | **exactement** ce que Brevo affiche dans « Login » — souvent `8xxxxxx001@smtp-brevo.com`, pas l'adresse du compte |
| SMTP account password | la clé SMTP Brevo (commence par `xsmtpsib-`) |
| SMTP security mode | STARTTLS (le mode du port 587) |

Faute de champ « répondre à », une réponse part vers l'adresse d'expéditeur.
Mettre `support@adfoot.org` plutôt que `no-reply@` si l'on veut lire ces
réponses — à condition que l'alias existe dans ImprovMX.

Dans le même écran, vérifier que les modèles **Réinitialisation du mot de
passe** et **Validation de l'adresse e-mail** sont bien en français. Le
sélecteur de langue fonctionne même quand l'édition du texte est verrouillée
(voir ci-dessous).

### Le nom affiché dans les messages : `%APP_NAME%`

Par défaut, les modèles disent « adfoot-production » — l'ID du projet, dans du
texte lu par les utilisateurs. Deux pièges découverts le 2026-08-27 :

- **L'édition des modèles peut être verrouillée.** Firebase répond *« Email
  template updates are currently unavailable for this project »*. Ce n'est pas
  une erreur de manipulation, et inutile d'ouvrir un ticket : `%APP_NAME%` est
  une variable, on corrige sa source.
- **Le champ « Public-facing name » n'existe plus** dans Paramètres du projet →
  Général. Il a été retiré de la console Firebase.

La source de `%APP_NAME%`, vérifiée en production, est le champ **App name**
de l'écran de consentement OAuth, côté Google Cloud :

```
https://console.cloud.google.com/auth/branding?project=adfoot-production
```

Y mettre `Adfoot`. L'assistant en quatre étapes (App Information → Audience →
Contact → Finish) ne s'est jamais exécuté sur ce projet : choisir **External**
(seule option hors Workspace), son adresse Google en contact, puis **ne rien
faire de plus** — aucun scope, pas de « Publish app », pas d'utilisateurs de
test. Ni l'app mobile ni le portail admin n'utilisent Google Sign-In, donc cet
écran ne sera jamais présenté à personne : il ne sert qu'à donner une valeur à
`%APP_NAME%`. Effet en quelques minutes, sur tous les modèles à la fois.

## Étape 5 — Vérifier

1. Depuis l'application, écran de connexion → « Mot de passe oublié ? » sur une
   adresse **Gmail**, puis recommencer sur une adresse **Outlook**.
2. Dans Gmail, ouvrir le message → menu ⋮ → **Afficher l'original**. La ligne
   qui compte est celle du milieu :
   - `DKIM: PASS` avec **`d=adfoot.org`** — c'est le seul verdict qui
     importe. Le domaine signataire doit être le vôtre, pas
     `firebaseapp.com`.
   - `DMARC: PASS` — il en découle.
   - `SPF: PASS` **mais avec un domaine Brevo**, pas `adfoot.org`, et c'est
     normal : Brevo fait partir le message depuis son propre domaine
     d'enveloppe. C'est pour cette raison que Brevo ne demande aucun
     enregistrement SPF, et que l'alignement DMARC repose entièrement sur le
     DKIM. Un SPF qui ne mentionne pas `adfoot.org` ici n'est pas un défaut.

   Si le message n'arrive pas du tout, ne pas chercher côté Firebase, qui ne
   remonte rien : le journal de Brevo (**Transactional → Logs**) montre chaque
   message et son sort — accepté, rejeté, bloqué.
3. Le message doit être en boîte de réception, sans bandeau d'avertissement.
4. Cliquer le lien et aller au bout de la réinitialisation, pour vérifier que
   rien n'a bougé côté application.

## Étape 6 — Activer l'envoi automatique de l'invitation

À faire **après** l'étape 5, avec les mêmes identifiants Brevo. Tant que cette
étape n'est pas faite, rien ne change : le portail affiche le lien et l'admin
le transmet à la main, comme aujourd'hui.

### Ce qui a changé dans le code

`provisionManagedAccount` et `resendManagedAccountInvite` expédient désormais
l'invitation elles-mêmes (`functions/src/email_delivery.ts`), **après** avoir
créé le compte, et **sans jamais échouer** : si le relais refuse, l'admin voit
un bandeau « Invitation à transmettre vous-même » et le lien est toujours là.
Le compte n'est jamais à moitié créé à cause d'un e-mail.

Le message ne contient qu'une seule action — définir le mot de passe. Le lien
de vérification d'adresse n'y est pas volontairement : terminer une
réinitialisation prouve qu'on a accès à la boîte, donc Firebase marque
l'adresse comme vérifiée tout seul.

### 1. Déposer la clé SMTP dans Secret Manager

```powershell
firebase functions:secrets:set BREVO_SMTP_KEY --project adfoot-production
```

La commande demande la valeur : coller la **clé SMTP Brevo** de l'étape 3
(pas le mot de passe du compte Brevo). Elle n'est jamais écrite sur disque et
n'apparaît pas dans la configuration lisible des Functions.

### 2. Renseigner le reste dans `functions/.env.production`

```
SMTP_HOST=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USER=<login Brevo, la même adresse qu'à l'étape 4>
MAIL_FROM_ADDRESS=no-reply@adfoot.org
MAIL_FROM_NAME=Adfoot
MAIL_REPLY_TO=support@adfoot.org
```

`SMTP_USER` vide = envoi désactivé. C'est l'interrupteur.

### 3. Déployer

```powershell
firebase deploy --only functions:provisionManagedAccount,functions:resendManagedAccountInvite --project adfoot-production
```

Le CLI accorde au compte de service d'exécution l'accès au secret. S'il ne
peut pas, il le dit explicitement — voir `IAM_SAFE_CONFIGURATION_RUNBOOK.md`.

### 4. Vérifier

Créer un compte de test sur **votre propre adresse** depuis le portail admin.
Trois choses à contrôler :

1. le bandeau vert « Invitation envoyée par e-mail » dans le portail ;
2. le message en boîte de réception, avec `DKIM: PASS` et `d=adfoot.org` ;
3. le bouton « Définir mon mot de passe » ouvre bien
   `adfoot.org/account/reset` et laisse saisir le mot de passe.

Dans les logs Functions, un envoi réussi écrit
`{"event":"account_invite_email_sent"}`. Un envoi impossible écrit
`account_invite_email_skipped` (non configuré) ou `account_invite_email_failed`
(refus du relais). Aucun de ces logs ne contient d'adresse e-mail : ils sont
lisibles par tout titulaire du rôle Logs Viewer.

### Retour arrière

Vider `SMTP_USER` dans `functions/.env.production` et redéployer les deux
callables. On revient exactement au fonctionnement actuel — lien affiché,
envoi manuel. Le secret peut rester en place, il ne sert plus.

## Étape 7 — Durcir DMARC, une à deux semaines plus tard

Laisser `p=none` le temps de lire les rapports reçus sur l'adresse `rua=`. Si
rien d'anormal ne remonte, passer à :

```
v=DMARC1; p=quarantine; rua=mailto:dmarc@adfoot.org
```

Ne pas sauter directement à `p=reject` : un SPF ou un DKIM mal aligné ferait
alors disparaître les messages sans avertissement.

---

## Pour plus tard : expédier aussi la réinitialisation nous-mêmes

Volontairement **non fait**, noté ici pour ne pas le redécouvrir.

L'invitation part de chez nous depuis l'étape 6. La réinitialisation, elle,
reste envoyée par Firebase. Le mécanisme pour la reprendre existe pourtant
déjà : `functions/src/admin_account_support.ts` sait forger un lien d'action
hébergé sur notre propre domaine (`generateHostedPasswordResetLink` →
`buildHostedAuthActionLink`), qui pointe vers
`https://adfoot.org/account/reset?...` et non vers le gestionnaire Firebase, et
la page correspondante est déployée (`site_pub/reset/index.html`).

Il manquerait :

1. un `onCall` `requestPasswordReset(email)` appelant
   `generateHostedPasswordResetLink` puis `sendAccountInviteEmail`
   (ou un équivalent au texte adapté) ;
2. la même réponse « succès » que le compte existe ou non, sinon la fonction
   devient un oracle révélant quelles adresses sont inscrites ;
3. une limitation de débit par adresse et par IP — l'invitation n'en a pas
   besoin (seul un admin authentifié peut la déclencher), celle-ci si, car
   elle serait ouverte à tout internet ;
4. côté mobile, remplacer `sendPasswordResetEmail` par l'appel au callable —
   donc un nouveau build et une publication Play.

Bénéfice secondaire, et c'est le vrai argument : le lien ne passerait plus par
`<authDomain>/__/auth/action`, donc l'App Link Android ne l'intercepterait
plus. La course au démarrage entre l'écran de réinitialisation et la
résolution de session disparaîtrait à la racine, au lieu d'être arbitrée par
`PasswordResetFlow`.

Ce qui l'a fait écarter aujourd'hui : les points 2 et 3 sont du code de
sécurité à écrire correctement, et le point 4 impose une publication Play,
là où l'étape 5 corrige le spam en trente secondes de console.

## Ce qui n'est **pas** la cause

Pour éviter d'y revenir :

- **Le domaine d'action des liens.** Le passer de
  `adfoot-production.firebaseapp.com` à `adfoot.org` (Authentication →
  Templates → domaine personnalisé) améliore l'apparence du lien, mais ne change
  pas l'expéditeur et donc pas le classement en spam.
- **Le contenu du message.** Les modèles Firebase sont déjà sobres, sans pièce
  jointe ni raccourcisseur d'URL.
- **Le code mobile.** `sendPasswordResetEmail` ne fait que demander l'envoi ; la
  composition et l'expédition appartiennent entièrement à Firebase.
- **Le SMTP et l'inscription par téléphone.** Ce sont deux sujets sans rapport :
  le SMTP envoie des e-mails, l'inscription par téléphone passe par des SMS
  facturés à l'unité (Firebase Phone Auth). Configurer Brevo ne rapproche en
  rien de l'inscription par téléphone.
