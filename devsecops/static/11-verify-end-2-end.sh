# Fetch the client API key so you can test
gcloud secrets versions access latest --secret=CLIENT_API_KEY
# Save it in SHELL for convenience:
export APIKEY=$(gcloud secrets versions access latest --secret=CLIENT_API_KEY)

# 1) Get a challenge (nonce)
curl -s "$PARENT_URL/prod/api/milapi/challenge?client_id=bankclient1" \
  -H "x-api-key: $APIKEY" | tee /tmp/chal.json

# 2) Compute proof locally and call an endpoint
NONCE=$(jq -r .nonce /tmp/chal.json)
# Get HMAC secret (for demo we compute here; in real client, they hold it)
export HMAC_SECRET=$(gcloud secrets versions access latest --secret=CHALLENGE_SECRET)
PROOF=$(python3 - <<PY
import hmac,hashlib,os,sys
print(hmac.new(os.environ["HMAC_SECRET"].encode(), os.environ["NONCE"].encode(), hashlib.sha256).hexdigest())
PY
)

# Call a mapped API (balance)
curl -s "$PARENT_URL/prod/api/milapi/acct/balance" \
  -H "x-api-key: $APIKEY" \
  -H "x-client-id: bankclient1" \
  -H "x-client-proof: $PROOF" | jq .

# Call a B-server API (loans eligibility)
curl -s "$PARENT_URL/prod/api/milapi/loans/eligibility" \
  -H "x-api-key: $APIKEY" \
  -H "x-client-id: bankclient1" \
  -H "x-client-proof: $PROOF" | jq .
