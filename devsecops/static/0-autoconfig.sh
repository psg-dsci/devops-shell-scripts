# Project (from your message)
export PROJECT_ID=$(gcloud config get project)
export PROJECT_NUMBER=756905382399
export REGION=us-south2
export ZONE=us-south2-b

gcloud config set project $PROJECT_ID
gcloud config set run/region $REGION
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
