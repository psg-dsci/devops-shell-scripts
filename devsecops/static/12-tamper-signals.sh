# Turn on packet-level VPC Flow Logs already done; now Log-based metrics for 401/403 spikes (anomaly hooks)
gcloud logging metrics create auth_denied_metric \
  --description="Auth failures" \
  --log-filter='resource.type="cloud_run_revision" AND severity>=WARNING AND textPayload:("api_key_invalid" OR "challenge_failed" OR "unauthorized")'

# Alert on auth failure surge (example: >100 in 1m)
gcloud alpha monitoring policies create --notification-channels="" \
  --policy-from-file=- <<'EOF'
{
  "displayName": "Auth Failure Surge",
  "combiner": "OR",
  "conditions": [{
    "displayName": "auth_denied_metric rate",
    "conditionThreshold": {
      "filter": "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/auth_denied_metric\"",
      "aggregations": [{"alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE"}],
      "comparison": "COMPARISON_GT",
      "thresholdValue": 100,
      "duration": "60s",
      "trigger": {"count": 1}
    }
  }]
}
EOF
