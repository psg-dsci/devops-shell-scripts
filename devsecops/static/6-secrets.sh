# Strong client API key + HMAC challenge secret (example)
CLIENT_API_KEY=$(openssl rand -hex 32)
CHALLENGE_SECRET=$(openssl rand -hex 64)

printf "%s" "$CLIENT_API_KEY"   | gcloud secrets create CLIENT_API_KEY   --data-file=-
printf "%s" "$CHALLENGE_SECRET" | gcloud secrets create CHALLENGE_SECRET --data-file=-

# Restrict access to parent-sa only
gcloud secrets add-iam-policy-binding CLIENT_API_KEY \
  --member="serviceAccount:parent-sa@unified-icon-469918-s7.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding CHALLENGE_SECRET \
  --member="serviceAccount:parent-sa@unified-icon-469918-s7.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
