# Create instances (Container-Optimized OS w/ container at boot). Tag for firewall.
gcloud compute instances create-with-container intranet-srv-a \
  --no-address --network=intranet-vpc --subnet=internal-subnet \
  --tags=internal-api-server \
  --service-account=internal-sa@unified-icon-469918-s7.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --container-image=us-south2-docker.pkg.dev/unified-icon-469918-s7/milapi-repo/intranet-api:1 \
  --container-env=GROUP=A,SERVICE_NAME=acct-core-A

gcloud compute instances create-with-container intranet-srv-b \
  --no-address --network=intranet-vpc --subnet=internal-subnet \
  --tags=internal-api-server \
  --service-account=internal-sa@unified-icon-469918-s7.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --container-image=us-south2-docker.pkg.dev/unified-icon-469918-s7/milapi-repo/intranet-api:1 \
  --container-env=GROUP=B,SERVICE_NAME=acct-core-B
