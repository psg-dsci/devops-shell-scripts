mkdir -p intranet-app && cd intranet-app

cat > requirements.txt <<'EOF'
flask==2.3.3
pyjwt==2.8.0
cryptography==42.0.5
gunicorn==21.2.0
EOF

cat > app.py <<'EOF'
import os, time, json, base64
from flask import Flask, request, jsonify
import jwt
from jwt import PyJWKClient
from cryptography.hazmat.primitives import serialization
from datetime import datetime, timezone

# Load KMS public key (PEM) baked into image at /app/kms_pub.pem
with open("/app/kms_pub.pem","rb") as f:
    PUB_PEM = f.read()
PUB_KEY = serialization.load_pem_public_key(PUB_PEM)

GROUP = os.environ.get("GROUP","A")   # "A" or "B"
SERVICE_NAME = os.environ.get("SERVICE_NAME","intranet-svc")

app = Flask(__name__)

def verify_kms_signed_jwt(token:str):
    # Verify ES256 signature & claims
    try:
        claims = jwt.decode(
            token,
            PUB_KEY,
            algorithms=["ES256"],
            audience="milapi-internal",
            options={"require": ["exp","iat","nbf","jti","iss","sub","aud"]}
        )
        # basic freshness check
        now = int(time.time())
        if claims["exp"] < now or claims["nbf"] > now:
            return None
        return claims
    except Exception as e:
        return None

@app.before_request
def enforce_auth():
    if request.path == "/healthz":
        return
    tok = request.headers.get("X-Auth-JWT","")
    claims = verify_kms_signed_jwt(tok)
    if not claims:
        return jsonify({"error":"unauthorized"}), 401
    # Optional per-call replay guard via jti + timestamp could be added (store jti in mem/redis)

@app.get("/healthz")
def health():
    return "ok", 200

# Five APIs per server (simulate banking)
@app.get("/acct/balance")
def balance():
    return jsonify({"service":SERVICE_NAME,"op":"balance","acct":"****6712","currency":"INR","balance":123456.78})

@app.get("/acct/transactions")
def txns():
    return jsonify({"service":SERVICE_NAME,"op":"transactions","last_10":[{"id":"T001","amt":-1200,"mcc":"5812"}]})

@app.post("/payment/initiate")
def pay():
    body = request.get_json(force=True, silent=True) or {}
    return jsonify({"service":SERVICE_NAME,"op":"payment_init","status":"QUEUED","req":body})

@app.get("/kyc/status")
def kyc():
    return jsonify({"service":SERVICE_NAME,"op":"kyc_status","status":"VERIFIED"})

@app.post("/alerts/subscribe")
def alerts():
    body = request.get_json(force=True, silent=True) or {}
    return jsonify({"service":SERVICE_NAME,"op":"alerts_subscribed","channel":body.get("channel","email")})

# Extra five for server B
@app.get("/cards/limit")
def cards_limit():
    return jsonify({"service":SERVICE_NAME,"op":"cards_limit","limit":200000})

@app.get("/loans/eligibility")
def loans_elig():
    return jsonify({"service":SERVICE_NAME,"op":"loans_eligibility","eligible":True,"max_amount":1500000})

@app.post("/fx/quote")
def fx_quote():
    body = request.get_json(force=True, silent=True) or {}
    return jsonify({"service":SERVICE_NAME,"op":"fx_quote","pair":body.get("pair","USDINR"),"quote":83.19})

@app.get("/profile/limits")
def profile_limits():
    return jsonify({"service":SERVICE_NAME,"op":"profile_limits","upi_per_tx":100000,"daily":200000})

@app.post("/risk/score")
def risk_score():
    body = request.get_json(force=True, silent=True) or {}
    return jsonify({"service":SERVICE_NAME,"op":"risk_score","score":745})
EOF

cat > Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py /app/app.py
COPY ../kms_pub.pem /app/kms_pub.pem
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
# Gunicorn (multi-worker) for perf
CMD exec gunicorn --workers 4 --threads 8 --bind 0.0.0.0:8080 app:app
EOF

# Build & push
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/milapi-repo/intranet-api:1
cd ..
