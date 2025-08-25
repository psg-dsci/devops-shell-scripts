# Artifact Registry for our containers
gcloud artifacts repositories create milapi-repo \
  --repository-format=docker --location=$REGION

# KMS for per-request JWT signing (admin can't export private key)
gcloud kms keyrings create milapi-kr --location=global
gcloud kms keys create auth-signing-key \
  --keyring=milapi-kr --location=global \
  --purpose=asymmetric-signing --default-algorithm=ec-sign-p256-sha256

# Allow ONLY parent-sa to sign (no one else, no export possible)
gcloud kms keys add-iam-policy-binding auth-signing-key \
  --keyring=milapi-kr --location=global \
  --member="serviceAccount:parent-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudkms.signerVerifier"

# Fetch public key (bake into internal servers to verify JWT)
gcloud kms keys versions get-public-key 1 \
  --key=auth-signing-key --keyring=milapi-kr --location=global \
  --output-file=kms_pub.pem
