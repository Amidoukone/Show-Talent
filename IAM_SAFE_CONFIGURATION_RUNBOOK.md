# IAM Safe Configuration Runbook (Adfoot)

Corriger l'IAM des Cloud Functions Gen2 sans interrompre le reste.

Projet actuel : **`adfoot-production`**
Région : `europe-west1`
Compte de déploiement : `koneamidou27@gmail.com`

> **Projet historique.** Les premières versions de ce document visaient
> `show-talent-5987d` et une fonction `sendVerificationReminder` qui n'existe
> plus. La procédure était bonne, les identifiants ne l'étaient plus, et un
> lecteur pressé suivait des commandes qui ne pouvaient pas marcher. Tout ce
> qui suit porte sur `adfoot-production`. Si vous intervenez encore sur
> l'ancien projet, remplacez `PROJECT_ID` et rien d'autre.

## Principe de sécurité

- Ne faire que des **ajouts** IAM. Aucun retrait pendant le diagnostic.
- Sauvegarder les policies avant toute modification.
- Redéployer uniquement les fonctions en échec, puis valider.

---

## Le symptôme, et ce qu'il n'est pas

Un déploiement se termine par :

```
Failed to get the IAM Policy on the Service
  projects/adfoot-production/locations/europe-west1/services/<service>
...
Unable to set the invoker for the IAM policy on the following functions:
        cleanupUnverifiedUsers(europe-west1)
        cvViewPage(europe-west1)
        drainPushCampaigns(europe-west1)
Error: There was an error deploying functions
```

**C'est un échec de lecture de policy, pas un échec de code.** Le compte qui
déploie n'a pas le droit de lire — donc d'écrire — la policy IAM des services
Cloud Run sous-jacents.

Trois faits à garder en tête avant de paniquer :

1. **Seules les fonctions à *invoker explicite* échouent.** Les callables sont
   invoquées via le SDK Firebase et n'en ont pas besoin. Échouent donc : les
   fonctions planifiées (`onSchedule`, appelées par Cloud Scheduler via un
   compte de service) et les fonctions HTTP publiques (`onRequest`, qui ont
   besoin de `allUsers`).
2. **Rien n'est retiré.** Le CLI a échoué à *réaffirmer* une liaison qui
   existait déjà depuis le déploiement précédent. Sur une *mise à jour* de
   fonction existante, la liaison en place n'est pas touchée.
3. **Le reste du déploiement a abouti.** Lire la liste des
   `Successful update operation.` : c'est elle qui dit ce qui est en ligne.

### Les trois services concernés chez nous

| Fonction | Source | Pourquoi un invoker |
| --- | --- | --- |
| `drainPushCampaigns` | `functions/src/fanout_campaigns.ts` | `onSchedule`, toutes les minutes — c'est elle qui envoie réellement les pushs de fanout offres/événements |
| `cleanupUnverifiedUsers` | `functions/src/cleanup.ts` | `onSchedule`, toutes les 24 h |
| `cvViewPage` | `functions/src/cv_view.ts` | `onRequest` public — les liens de partage de CV, qui exigent `allUsers` |

Le nom du service Cloud Run est le nom de la fonction **en minuscules** :
`drainpushcampaigns`, `cleanupunverifiedusers`, `cvviewpage`.

---

## 1) Vérifier d'abord si quelque chose est réellement cassé

Avant de toucher à l'IAM. `drainPushCampaigns` tourne **toutes les minutes**,
donc la réponse arrive tout de suite :

```powershell
firebase.cmd functions:log --only drainPushCampaigns --lines 20 --project adfoot-production
```

Des exécutions récentes = l'invoker est intact, le déploiement a seulement
échoué à le réécrire. Des `403` ou plus aucune exécution = la liaison est
réellement absente.

La fonction HTTP publique se teste directement :

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" https://cvviewpage-jfxldioblq-ew.a.run.app
```

Un `403` signifie que `allUsers` a disparu. Un `404`/`405` est normal : la page
exige un ticket, et elle a répondu — donc elle est invocable.

Et le relevé d'ensemble des erreurs depuis le déploiement :

```powershell
node scripts/check-production-runtime.mjs <ISO-du-deploiement> --firebase-cli-auth
```

## 2) Cloud Shell

`gcloud` n'est pas installé sur le poste de développement. Utiliser Cloud Shell
depuis la console GCP, projet `adfoot-production`.

```bash
PROJECT_ID="adfoot-production"
REGION="europe-west1"
DEPLOYER_MEMBER="user:koneamidou27@gmail.com"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
echo "Project number: $PROJECT_NUMBER"
```

## 3) Sauvegarde (obligatoire)

```bash
mkdir -p iam-backups
gcloud projects get-iam-policy "$PROJECT_ID" \
  --format=json > "iam-backups/${PROJECT_ID}-project-policy-before.json"

for SVC in drainpushcampaigns cleanupunverifiedusers cvviewpage; do
  gcloud run services get-iam-policy "$SVC" \
    --region="$REGION" --project="$PROJECT_ID" \
    --format=json > "iam-backups/${SVC}-run-policy-before.json" 2>/dev/null \
    || echo "policy illisible pour $SVC (c'est le symptôme)"
done
```

## 4) Lire les rôles actuels du déployeur

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${DEPLOYER_MEMBER}" \
  --format="table(bindings.role)"
```

Le rôle qui manque presque toujours est **`roles/run.admin`** :
`roles/cloudfunctions.developer` ne permet pas de modifier une policy IAM, et
depuis Gen2 l'invoker est une policy **Cloud Run**, pas Cloud Functions.

## 5) Ajouter uniquement les rôles manquants

```bash
for ROLE in \
  roles/cloudfunctions.admin \
  roles/run.admin \
  roles/iam.serviceAccountUser \
  roles/cloudbuild.builds.editor \
  roles/artifactregistry.writer \
  roles/eventarc.admin \
  roles/pubsub.admin \
  roles/cloudscheduler.admin
do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="$DEPLOYER_MEMBER" \
    --role="$ROLE"
done
```

Dans la plupart des cas `roles/run.admin` seul suffit ; la liste complète est
là pour un poste qui n'a jamais déployé.

## 6) Réparer l'invoker à la main, si l'étape 1 a montré une vraie coupure

### Fonctions planifiées

```bash
gcloud scheduler jobs list --location="$REGION" --project="$PROJECT_ID"

JOB_NAME="firebase-schedule-drainPushCampaigns-${REGION}"
CALLER_SA=$(gcloud scheduler jobs describe "$JOB_NAME" \
  --location="$REGION" --project="$PROJECT_ID" \
  --format="value(httpTarget.oidcToken.serviceAccountEmail)")
echo "Scheduler caller SA: $CALLER_SA"
```

Si `CALLER_SA` est vide, repli sûr :

```bash
CALLER_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
```

```bash
gcloud run services add-iam-policy-binding drainpushcampaigns \
  --region="$REGION" --project="$PROJECT_ID" \
  --member="serviceAccount:${CALLER_SA}" \
  --role="roles/run.invoker"
```

Même chose pour `cleanupunverifiedusers` avec
`firebase-schedule-cleanupUnverifiedUsers-${REGION}`.

### Fonction HTTP publique

`cvViewPage` sert les liens de partage de CV à des personnes non connectées :
son invoker doit être `allUsers`.

```bash
gcloud run services add-iam-policy-binding cvviewpage \
  --region="$REGION" --project="$PROJECT_ID" \
  --member="allUsers" \
  --role="roles/run.invoker"
```

Si cette commande est refusée alors que `roles/run.admin` est bien accordé, la
cause est une **org policy de partage restreint**
(`constraints/iam.allowedPolicyMemberDomains`), qui interdit `allUsers`. Elle
se lève au niveau de l'organisation, pas du projet — et c'est la seule des
trois réparations qui peut demander quelqu'un d'autre.

## 7) Redéployer uniquement les fonctions en échec

```powershell
firebase.cmd deploy --only functions:drainPushCampaigns,functions:cleanupUnverifiedUsers,functions:cvViewPage --project adfoot-production
```

Ne pas relancer `npm run functions:deploy:production` : il redéploie les 57
fonctions pour en réparer trois.

## 8) Tester sans attendre la planification

```bash
gcloud scheduler jobs run "$JOB_NAME" --location="$REGION" --project="$PROJECT_ID"
```

```powershell
firebase.cmd functions:log --only drainPushCampaigns --lines 50 --project adfoot-production
```

## 9) Validation finale

- Le déploiement n'affiche plus `Unable to set the invoker for the IAM policy`.
- Les jobs scheduler s'exécutent sans `403`.
- `cvviewpage` répond autre chose qu'un `403`.
- Aucune liaison IAM n'a été retirée.

## 10) Rollback

Retirer uniquement les liaisons ajoutées, une par une :

```bash
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="$DEPLOYER_MEMBER" \
  --role="roles/run.admin"
```

---

## Ce que ce défaut coûte si on l'ignore

`drainPushCampaigns` est la fonction qui **envoie réellement** les
notifications de fanout : `sendOfferFanout` et `sendEventFanout` ne font
qu'empiler une campagne, c'est elle qui la vide. Un invoker cassé là veut dire
que les recruteurs publient des offres dont personne n'est prévenu — sans
aucune erreur visible côté application, puisque le callable a répondu « file
d'attente acceptée ».

C'est la raison d'être de l'étape 1 : savoir avant de supposer.
