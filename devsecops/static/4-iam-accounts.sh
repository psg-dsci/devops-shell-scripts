# SA for internal servers (GCE instances)
gcloud iam service-accounts create internal-sa --display-name="Internal SA"
# SA for parent Cloud Run service
gcloud iam service-accounts create parent-sa --display-name="Parent API SA"

# Minimal roles: write logs/metrics, read secrets (parent only), KMS sign (parent only), Artifact Registry reader (VMs pull images)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:internal-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:internal-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:internal-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:parent-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:parent-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:parent-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
