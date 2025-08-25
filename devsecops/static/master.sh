
# 0. Set project & core variables
bash 0-autoconfig.sh

# 1. Enable API's
bash 1-enable-api.sh

# 2. Networking: VPC, subnets, flow logs, connector
bash 2-networking.sh

# 3. Firewall: lock down intranet, allow only from connector
bash firewall.sh

# 4. IAM service accounts & minimal roles
bash 4-iam-accounts.sh

# 5. KMS: HSM-backed signing key (admin cannot extract), + repo for images
bash 5-kms-key.sh

# 6. Secrets: partner API key + HMAC secret for challenge
bash 6-secrets.sh

# 7. Internal servers (10 banking APIs total) – build image
bash 7-internal-servers.sh

# 8. Create two isolated GCE servers (no public IP), auto-run containers
bash 8-isolated-container.sh

# 9. Parent API (public) – build & deploy (Cloud Run)
bash 9-parent-api-cloud-run.sh

# 10. PENDING - (Optional but recommended) HTTPS LB + Cloud Armor WAF (custom domain) - PENDING

# 11. Verify end-to-end (challenge -> signed JWT -> intranet calls)
bash 11-verify-end-2-end.sh

# 12. Observability & tamper signals
bash 12-tamper-signals.sh