# IAM Safe Configuration Runbook (Adfoot / Show-Talent)

Objectif: corriger et stabiliser IAM pour Functions Gen2 (dont `sendVerificationReminder`) sans interrompre le reste.

Projet: `show-talent-5987d`  
Région: `europe-west1`  
Compte deploy courant observé: `koneamidou27@gmail.com`  
Project Number observé: `43422248234`

## Principe de sécurité

- Ne faire que des ajouts IAM (pas de suppression au début).
- Sauvegarder les policies avant modification.
- Déployer uniquement la fonction en échec, puis valider.

## 1) Exécuter depuis Cloud Shell (recommandé)

`gcloud` n'est pas installé localement sur ce poste. Utiliser Cloud Shell dans GCP.

## 2) Variables

```bash
PROJECT_ID="show-talent-5987d"
REGION="europe-west1"
DEPLOYER_EMAIL="koneamidou27@gmail.com"
DEPLOYER_MEMBER="user:${DEPLOYER_EMAIL}"
PROJECT_NUMBER="43422248234"
RUN_SERVICE="sendverificationreminder"
```

## 3) Backup IAM (obligatoire)

```bash
mkdir -p iam-backups
gcloud projects get-iam-policy "$PROJECT_ID" \
  --format=json > "iam-backups/${PROJECT_ID}-project-policy-before.json"

gcloud run services get-iam-policy "$RUN_SERVICE" \
  --region="$REGION" --project="$PROJECT_ID" \
  --format=json > "iam-backups/${RUN_SERVICE}-run-policy-before.json"
```

## 4) Vérifier les rôles actuels du deployer

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${DEPLOYER_MEMBER}" \
  --format="table(bindings.role)"
```

## 5) Ajouter uniquement les rôles requis (si manquants)

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

## 6) Corriger l’invoker du service Cloud Run du scheduler

Trouver le job scheduler (nom exact):

```bash
gcloud scheduler jobs list --location="$REGION" --project="$PROJECT_ID"
```

Lire le service account utilisé pour appeler la fonction:

```bash
JOB_NAME="firebase-schedule-sendVerificationReminder-${REGION}"
CALLER_SA=$(gcloud scheduler jobs describe "$JOB_NAME" \
  --location="$REGION" --project="$PROJECT_ID" \
  --format="value(httpTarget.oidcToken.serviceAccountEmail)")
echo "Scheduler caller SA: $CALLER_SA"
```

Si `CALLER_SA` est vide, fallback sûr:

```bash
CALLER_SA="service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
echo "Fallback Scheduler SA: $CALLER_SA"
```

Ajouter `roles/run.invoker` sur le service:

```bash
gcloud run services add-iam-policy-binding "$RUN_SERVICE" \
  --region="$REGION" --project="$PROJECT_ID" \
  --member="serviceAccount:${CALLER_SA}" \
  --role="roles/run.invoker"
```

Option de compatibilité (si votre job utilise le compute default SA):

```bash
gcloud run services add-iam-policy-binding "$RUN_SERVICE" \
  --region="$REGION" --project="$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/run.invoker"
```

## 7) Redéployer uniquement la fonction en échec

Depuis votre repo local:

```bash
firebase.cmd deploy --only functions:sendVerificationReminder --project show-talent-5987d
```

## 8) Test immédiat sans attendre 24h

```bash
gcloud scheduler jobs run "$JOB_NAME" --location="$REGION" --project="$PROJECT_ID"
```

Puis vérifier les logs:

```bash
firebase.cmd functions:log --only sendVerificationReminder --lines 50 --project show-talent-5987d
```

## 9) Validation finale

- La commande de deploy ne doit plus afficher:
  - `Unable to set the invoker for the IAM policy`
- Le job scheduler doit exécuter la fonction sans `403`.
- Les autres fonctions restent inchangées (on n'a fait aucun retrait IAM).

## 10) Rollback (si besoin)

Retirer uniquement les bindings ajoutés pendant l’opération:

```bash
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="$DEPLOYER_MEMBER" \
  --role="roles/run.admin"
```

Même logique pour les autres rôles ajoutés (un rôle à la fois).
