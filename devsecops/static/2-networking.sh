# VPC + subnets (enable VPC Flow Logs + Private Google Access so VMs can reach Google APIs without public IPs)
gcloud compute networks create intranet-vpc --subnet-mode=custom

gcloud compute networks subnets create internal-subnet \
  --network=intranet-vpc --range=10.10.0.0/16 --region=$REGION \
  --enable-flow-logs --enable-private-ip-google-access

gcloud compute networks subnets create dmz-subnet \
  --network=intranet-vpc --range=10.20.0.0/16 --region=$REGION \
  --enable-flow-logs --enable-private-ip-google-access

# Serverless VPC Access connector for the parent API (egress to VPC only)
gcloud compute networks vpc-access connectors create dmz-connector \
  --network=intranet-vpc --region=$REGION --range=10.8.0.0/28
