# Create instances (Container-Optimized OS w/ container at boot). Tag for firewall.
gcloud compute instances create-with-container intranet-srv-a \
  --no-address --network=intranet-vpc --subnet=internal-subnet \
  --tags=internal-api-server \
  --service-account=internal-sa@$PROJECT_ID.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --container-image=$REGION-docker.pkg.dev/$PROJECT_ID/milapi-repo/intranet-api:1 \
  --container-env=GROUP=A,SERVICE_NAME=acct-core-A

gcloud compute instances create-with-container intranet-srv-b \
  --no-address --network=intranet-vpc --subnet=internal-subnet \
  --tags=internal-api-server \
  --service-account=internal-sa@$PROJECT_ID.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --container-image=$REGION-docker.pkg.dev/$PROJECT_ID/milapi-repo/intranet-api:1 \
  --container-env=GROUP=B,SERVICE_NAME=acct-core-B
