# 0) Point to your bundle
B="instance-20250731-114417.us-east1-b.c.dmjone.internal_oneclick_20250824_081819.tgz"

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
