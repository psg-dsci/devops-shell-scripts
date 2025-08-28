mkdir -p parent-api && cd parent-api

cat > requirements.txt <<'EOF'
fastapi==0.111.0
uvicorn==0.30.1
google-cloud-secret-manager==2.20.2
google-cloud-kms==2.24.0
httpx==0.27.0
pydantic==2.7.4
pyjwt==2.8.0
EOF

cat > main.py <<'EOF'
import os, time, hmac, hashlib, uuid, asyncio
from typing import Optional
from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel
import httpx, jwt
from google.cloud import secretmanager, kms

PROJECT_ID = os.environ["PROJECT_ID"]
REGION     = os.environ["REGION"]
KMS_LOC    = "global"
KEY_RING   = "milapi-kr"
KEY_ID     = "auth-signing-key"
INTRA_A    = os.environ["INTRA_A_IP"]  # VM A internal IP
INTRA_B    = os.environ["INTRA_B_IP"]  # VM B internal IP

# Cached secrets
_sm = secretmanager.SecretManagerServiceClient()
def get_secret(name: str) -> str:
    ver = "latest"
    res = _sm.access_secret_version(name=f"projects/{PROJECT_ID}/secrets/{name}/versions/{ver}")
    return res.payload.data.decode()

CLIENT_API_KEY = None
CHALLENGE_SECRET = None

app = FastAPI(title="Parent MilAPI", version="1.0")

# simple in-memory challenges (for demo). In prod, use Redis/Memcache with TTL.
_challenges = {}

class PayReq(BaseModel):
    to: str
    amount: float
    currency: str = "INR"

def sign_jwt_with_kms(claims: dict) -> str:
    # Create header+payload, ES256 sign using KMS
    header = {"alg":"ES256","typ":"JWT"}
    import json, base64
    def b64url(x: bytes) -> bytes:
        return base64.urlsafe_b64encode(x).rstrip(b"=")
    encoded_header  = b64url(json.dumps(header,separators=(",",":")).encode())
    encoded_payload = b64url(json.dumps(claims,separators=(",",":")).encode())
    signing_input = encoded_header + b"." + encoded_payload

    client = kms.KeyManagementServiceClient()
    name = client.crypto_key_version_path(PROJECT_ID, KMS_LOC, KEY_RING, KEY_ID, "1")
    digest = hashlib.sha256(signing_input).digest()
    resp = client.asymmetric_sign(
        request={"name": name, "digest": {"sha256": digest}}
    )
    sig = resp.signature
    jwt_compact = signing_input.decode() + "." + b64url(sig).decode()
    return jwt_compact

async def call_intranet(path: str, method="GET", json_body=None):
    # Choose target based on path (first five -> A; next five -> B)
    if path in ["/acct/balance","/acct/transactions","/payment/initiate","/kyc/status","/alerts/subscribe"]:
        host = INTRA_A
    else:
        host = INTRA_B

    now = int(time.time())
    claims = {
        "iss":"parent-milapi",
        "sub":"parent-milapi",
        "aud":"milapi-internal",
        "nbf": now - 5,
        "iat": now,
        "exp": now + 60,  # 60s validity
        "jti": str(uuid.uuid4())
    }
    token = sign_jwt_with_kms(claims)

    url = f"http://{host}:8080{path}"
    async with httpx.AsyncClient(timeout=4.0) as client:
        if method == "GET":
            r = await client.get(url, headers={"X-Auth-JWT":token})
        else:
            r = await client.post(url, json=json_body or {}, headers={"X-Auth-JWT":token})
    if r.status_code != 200:
        raise HTTPException(status_code=r.status_code, detail=r.text)
    return r.json()

@app.on_event("startup")
def _init():
    global CLIENT_API_KEY, CHALLENGE_SECRET
    CLIENT_API_KEY   = get_secret("CLIENT_API_KEY")
    CHALLENGE_SECRET = get_secret("CHALLENGE_SECRET")

@app.get("/prod/api/milapi/challenge")
def challenge(client_id: str, x_api_key: Optional[str]=Header(None)):
    if x_api_key != CLIENT_API_KEY:
        raise HTTPException(status_code=401, detail="api_key_invalid")
    nonce = str(uuid.uuid4())
    _challenges[client_id] = {"nonce": nonce, "ts": time.time()}
    return {"client_id":client_id, "nonce":nonce, "algo":"HMAC_SHA256(nonce,shared_secret)"}

def verify_proof(client_id: str, proof: str):
    ent = _challenges.get(client_id)
    if not ent: return False
    if time.time() - ent["ts"] > 60: return False
    expected = hmac.new(CHALLENGE_SECRET.encode(), ent["nonce"].encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, proof)

@app.get("/prod/api/milapi/acct/balance")
async def acct_balance(x_api_key: Optional[str]=Header(None),
                       x_client_id: Optional[str]=Header(None),
                       x_client_proof: Optional[str]=Header(None)):
    if x_api_key != CLIENT_API_KEY: raise HTTPException(status_code=401, detail="api_key_invalid")
    if not (x_client_id and x_client_proof and verify_proof(x_client_id, x_client_proof)):
        raise HTTPException(status_code=401, detail="challenge_failed")
    return await call_intranet("/acct/balance","GET")

@app.get("/prod/api/milapi/acct/transactions")
async def acct_txn(x_api_key: Optional[str]=Header(None),
                   x_client_id: Optional[str]=Header(None),
                   x_client_proof: Optional[str]=Header(None)):
    if x_api_key != CLIENT_API_KEY: raise HTTPException(status_code=401, detail="api_key_invalid")
    if not (x_client_id and x_client_proof and verify_proof(x_client_id, x_client_proof)):
        raise HTTPException(status_code=401, detail="challenge_failed")
    return await call_intranet("/acct/transactions","GET")

@app.post("/prod/api/milapi/payment/initiate")
async def pay_initiate(req: PayReq,
                       x_api_key: Optional[str]=Header(None),
                       x_client_id: Optional[str]=Header(None),
                       x_client_proof: Optional[str]=Header(None)):
    if x_api_key != CLIENT_API_KEY: raise HTTPException(status_code=401, detail="api_key_invalid")
    if not (x_client_id and x_client_proof and verify_proof(x_client_id, x_client_proof)):
        raise HTTPException(status_code=401, detail="challenge_failed")
    return await call_intranet("/payment/initiate","POST", json_body=req.dict())

# map a couple to server B too (example)
@app.get("/prod/api/milapi/cards/limit")
async def cards_limit(x_api_key: Optional[str]=Header(None),
                      x_client_id: Optional[str]=Header(None),
                      x_client_proof: Optional[str]=Header(None)):
    if x_api_key != CLIENT_API_KEY: raise HTTPException(status_code=401, detail="api_key_invalid")
    if not (x_client_id and x_client_proof and verify_proof(x_client_id, x_client_proof)):
        raise HTTPException(status_code=401, detail="challenge_failed")
    return await call_intranet("/cards/limit","GET")

@app.get("/prod/api/milapi/loans/eligibility")
async def loans_elig(x_api_key: Optional[str]=Header(None),
                     x_client_id: Optional[str]=Header(None),
                     x_client_proof: Optional[str]=Header(None)):
    if x_api_key != CLIENT_API_KEY: raise HTTPException(status_code=401, detail="api_key_invalid")
    if not (x_client_id and x_client_proof and verify_proof(x_client_id, x_client_proof)):
        raise HTTPException(status_code=401, detail="challenge_failed")
    return await call_intranet("/loans/eligibility","GET")
EOF

cat > Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py /app/main.py
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8080","--workers","4"]
EOF

# Build & push parent
gcloud builds submit --tag us-south2-docker.pkg.dev/unified-icon-469918-s7/milapi-repo/parent-api:1


# 9.1 Get the internal IPs of the two intranet servers
IP_A=$(gcloud compute instances describe intranet-srv-a --format="get(networkInterfaces[0].networkIP)")
IP_B=$(gcloud compute instances describe intranet-srv-b --format="get(networkInterfaces[0].networkIP)")
echo $IP_A $IP_B

# 9.2. Deploy Cloud Run parent API (public), VPC-egress only
gcloud run deploy parent-milapi \
  --image us-south2-docker.pkg.dev/unified-icon-469918-s7/milapi-repo/parent-api:1 \
  --service-account parent-sa@unified-icon-469918-s7.iam.gserviceaccount.com \
  --set-env-vars PROJECT_ID=unified-icon-469918-s7,REGION=us-south2,INTRA_A_IP=$IP_A,INTRA_B_IP=$IP_B \
  --vpc-connector dmz-connector --vpc-egress all-traffic \
  --allow-unauthenticated \
  --max-instances 1000 --concurrency 200

# 9.3 Cloud Run URL
PARENT_URL=$(gcloud run services describe parent-milapi --format='value(status.url)')
echo $PARENT_URL
