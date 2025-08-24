A quick, no-nonsense way to **prove the bundle is good** *before* you delete the VM, and then how to **smoke-test the restore** on a fresh box.

---

## A) Verify the backup bundle (on the current VM)

> Replace the path in `B=…` with your bundle:
> `/root/instance-20250731-114417.us-east1-b.c.dmjone.internal_oneclick_20250824_081819.tgz`

```bash
# 0) Point to your bundle
B="/root/instance-20250731-114417.us-east1-b.c.dmjone.internal_oneclick_20250824_081819.tgz"

# 1) Archive integrity + required top-level payload bits exist
tar -tzf "$B" >/dev/null && echo "OK: bundle readable"
tar -tzf "$B" | grep -E \
'payload/(restore\.sh|metadata/meta\.json|home/home\.tar\.gz|nginx/nginx\.tar\.gz|systemd/systemd_units\.tar\.gz)' \
| sed -n '1,999p'

# 2) Inspect contents (nested tars are present and readable)
T="$(mktemp -d)"
tar -xzf "$B" -C "$T"
ls -lh "$T/payload"
tar -tzf "$T/payload/home/home.tar.gz"     | head
tar -tzf "$T/payload/nginx/nginx.tar.gz"   | grep sites-available | head
[ -f "$T/payload/letsencrypt/letsencrypt.tar.gz" ] && \
  tar -tzf "$T/payload/letsencrypt/letsencrypt.tar.gz" | head || echo "No LE tar (will re-issue certs)."

# 3) Metadata + restore script syntax
python3 -m json.tool "$T/payload/metadata/meta.json"
bash -n "$T/payload/restore.sh" && echo "OK: restore.sh syntax"

# 4) Wheels (offline deps cache) present if you had requirements.txt
if [ -d "$T/payload/wheels" ]; then
  echo "Wheel files:"; ls -1 "$T/payload/wheels" | sed -n '1,15p'
fi

# 5) Create a checksum for transfer integrity
sha256sum "$B" | tee "$B.sha256"
```

**What “good” looks like**

* Step 1 prints “OK: bundle readable” and shows the five key paths.
* Step 2 can list files inside each nested tar (not empty / not errors).
* Step 3 pretty-prints JSON and “OK: restore.sh syntax”.
* Step 4 shows a bunch of `*.whl` names (if your app had `requirements.txt`).
* Step 5 gives you a SHA256 hash to verify *after* copying the bundle elsewhere.

---

## B) After you copy the bundle off the server

On the destination (or just another box) **verify the copy**:

```bash
# Put .tgz and .sha256 in the same directory first
sha256sum -c /path/to/instance-..._oneclick_20250824_081819.tgz.sha256
# Expect: "<filename>: OK"
```

---

## C) Smoke-test the restore on a fresh VM

> Use a disposable VM. This will install packages, Nginx, a systemd service, etc.
> You can override the defaults safely, e.g. different service name/port:

```bash
# Copy both files to the new VM, then:
bash oneclick.sh restore /path/to/instance-..._oneclick_20250824_081819.tgz
# or with overrides to avoid clashing names/ports while testing:
sudo DOMAIN=test.example SERVICE=airesume-test APP_PORT=8010 \
     bash oneclick.sh restore /path/to/instance-...tgz
```

**Post-restore checks (all should succeed):**

```bash
# App service up?
systemctl is-active airesume         # (or your SERVICE) -> active

# App port listening?
ss -ltnp | grep :8000               # (or APP_PORT)

# App responds locally?
curl -I http://127.0.0.1:8000       # expect HTTP/200 or your app’s default response

# Nginx config OK and serving your domain mapping?
sudo nginx -t
curl -I -H "Host: jdtuning.dmj.one" http://127.0.0.1  # expect 200/301

# TLS present (if you restored/issued certs)?
sudo certbot certificates | sed -n '/jdtuning\.dmj\.one/,+8p'

# Firewall restored and open for web?
sudo ufw status

# Crons restored (if you had any)?
crontab -l || true
sudo crontab -l || true

# Service logs (look for errors)
journalctl -u airesume -n 200 --no-pager
```

If those all pass, you’re green to decommission the old VM.
If anything fails, paste the exact command output and I’ll pinpoint the fix.
