# backup-verify.sh

chmod +x oneclick.sh

bash ./oneclick.sh backup

B=$(ls -1t ~/*_oneclick_*.tgz | head -1)   # newest bundle
echo "Bundle: $B"

# quick integrity:
tar -tzf "$B" >/dev/null && echo "OK: archive listable"
T=$(mktemp -d); tar -xzf "$B" -C "$T"
bash -n "$T/payload/restore.sh" && echo "OK: restore.sh syntax"
python3 -m json.tool "$T/payload/metadata/meta.json" | sed -n '1,20p'
