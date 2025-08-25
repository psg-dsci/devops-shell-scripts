# Deny everything to internal servers by default (high priority deny)
gcloud compute firewall-rules create deny-all-to-internal \
  --network=intranet-vpc --direction=INGRESS --priority=100 \
  --action=DENY --rules=all --target-tags=internal-api-server \
  --source-ranges=0.0.0.0/0

# Allow ONLY Serverless VPC Access connector range to talk to internal servers on 8080 (our API port)
gcloud compute firewall-rules create allow-connector-to-internal-apis \
  --network=intranet-vpc --direction=INGRESS --priority=10 \
  --action=ALLOW --rules=tcp:8080 \
  --target-tags=internal-api-server --source-ranges=10.8.0.0/28
