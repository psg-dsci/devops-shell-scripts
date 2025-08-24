#!/usr/bin/env bash
# oneclick.sh — Backup & Restore for your server (Ubuntu/Debian)
# Usage:
#   BACKUP  : bash oneclick.sh backup
#   RESTORE : bash oneclick.sh restore /path/to/bundle.tgz
# Optional env (both modes): DOMAIN, SERVICE, APP_DIR, APP_PORT
#
# Safe-by-default, idempotent, logs to ~/oneclick/logs/

set -euo pipefail

### ----------- Config (overridable via env) -----------
DOMAIN="${DOMAIN:-jdtuning.dmj.one}"
SERVICE="${SERVICE:-airesume}"
APP_DIR="${APP_DIR:-$HOME/AI-Resume-Optimizer/AI_Resume_Optimizer}"
APP_PORT="${APP_PORT:-8000}"
PYTHON_BIN="${PYTHON_BIN:-python3}"      # will detect
EMAIL_DEFAULT="admin@${DOMAIN}"          # used for certbot if needed
NOW="$(date +%Y%m%d_%H%M%S)"
HOST="$(hostname -f 2>/dev/null || hostname)"
WORKROOT="$HOME/oneclick"
LOGDIR="$WORKROOT/logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/run_${NOW}.log"
exec > >(tee -a "$LOG") 2>&1

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need_root() { [ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"; }

detect_python() {
  if command -v python3 >/dev/null; then echo "python3"; return; fi
  if command -v python >/dev/null; then echo "python"; return; fi
  echo "python3" # best effort
}

### ----------- BACKUP -----------
backup() {
  echo "==> Starting BACKUP on $HOST @ $NOW"
  need_cmd tar
  PYBIN="$(detect_python)"
  STAGE="$WORKROOT/stage_${NOW}"
  PAYLOAD="$STAGE/payload"
  mkdir -p "$PAYLOAD"

  echo "==> Collecting metadata & package lists"
  mkdir -p "$PAYLOAD/metadata"
  uname -a > "$PAYLOAD/metadata/uname.txt" || true
  lsb_release -a > "$PAYLOAD/metadata/lsb_release.txt" 2>/dev/null || true
  dpkg --get-selections > "$PAYLOAD/metadata/dpkg.list" 2>/dev/null || true
  apt-mark showmanual > "$PAYLOAD/metadata/apt.manual" 2>/dev/null || true
  env | sort > "$PAYLOAD/metadata/env.snapshot" || true
  echo "{\"domain\":\"$DOMAIN\",\"service\":\"$SERVICE\",\"app_dir\":\"$APP_DIR\",\"app_port\":\"$APP_PORT\",\"host\":\"$HOST\",\"ts\":\"$NOW\"}" > "$PAYLOAD/metadata/meta.json"

  echo "==> Saving crontabs"
  mkdir -p "$PAYLOAD/crontab"
  crontab -l > "$PAYLOAD/crontab/user.cron" 2>/dev/null || true
  sudo crontab -l > "$PAYLOAD/crontab/root.cron" 2>/dev/null || true

  echo "==> Saving firewall rules"
  mkdir -p "$PAYLOAD/firewall"
  (sudo ufw status numbered || true) > "$PAYLOAD/firewall/ufw.status"
  sudo iptables-save > "$PAYLOAD/firewall/iptables.rules" 2>/dev/null || true

  echo "==> Staging HOME (excluding caches)"
  mkdir -p "$PAYLOAD/home"
  # Full home, but drop heavy caches/logs (still captures .ssh, .bashrc, keys, etc.)
  tar -C "$HOME" \
      --exclude='.cache' \
      --exclude='.local/share/Trash' \
      --exclude='.npm' \
      --exclude='.cargo' \
      --exclude='.pyenv' \
      --exclude='.nvm' \
      --exclude='**/__pycache__' \
      --exclude='**/*.pyc' \
      -czf "$PAYLOAD/home/home.tar.gz" .

  echo "==> Capturing Nginx & TLS"
  mkdir -p "$PAYLOAD/nginx"
  sudo tar -czf "$PAYLOAD/nginx/nginx.tar.gz" /etc/nginx 2>/dev/null || true

  mkdir -p "$PAYLOAD/letsencrypt"
  if [ -d /etc/letsencrypt ]; then
    sudo tar -czf "$PAYLOAD/letsencrypt/letsencrypt.tar.gz" /etc/letsencrypt || true
  fi

  echo "==> Capturing systemd service units"
  mkdir -p "$PAYLOAD/systemd"
  # Grab all units; they’re small and restore filters safely.
  sudo tar -czf "$PAYLOAD/systemd/systemd_units.tar.gz" /etc/systemd/system || true

  echo "==> Offline wheelhouse for Python deps (if requirements.txt exists)"
  WHEELDIR="$PAYLOAD/wheels"; mkdir -p "$WHEELDIR"
  if [ -f "$APP_DIR/requirements.txt" ]; then
    # Try using an existing venv; else temporary venv
    if [ -x "$APP_DIR/.venv/bin/pip" ]; then
      "$APP_DIR/.venv/bin/pip" freeze > "$PAYLOAD/metadata/requirements.freeze" || true
      "$APP_DIR/.venv/bin/pip" download -r "$APP_DIR/requirements.txt" -d "$WHEELDIR" || true
    else
      "$PYBIN" -m venv "$STAGE/.tmpvenv"
      source "$STAGE/.tmpvenv/bin/activate"
      pip install -U pip >/dev/null 2>&1 || true
      pip freeze > "$PAYLOAD/metadata/requirements.freeze" || true
      pip download -r "$APP_DIR/requirements.txt" -d "$WHEELDIR" || true
      deactivate
      rm -rf "$STAGE/.tmpvenv"
    fi
  fi

  echo "==> Writing self-contained restore script into payload"
  cat > "$PAYLOAD/restore.sh" <<'RESTORESH'
#!/usr/bin/env bash
set -euo pipefail
need_root() { [ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"; }
need_root

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META="$WORKDIR/metadata/meta.json"

get_json() { python3 - "$1" "$META" <<'PY'
import json,sys
key = sys.argv[1]; f = sys.argv[2]
data=json.load(open(f))
print(data.get(key,""))
PY
}

DOMAIN="${DOMAIN:-$(get_json domain)}"
SERVICE="${SERVICE:-$(get_json service)}"
APP_DIR_RAW="${APP_DIR:-$(get_json app_dir)}"
APP_DIR="${APP_DIR_RAW/#\~/$HOME}"
APP_PORT="${APP_PORT:-$(get_json app_port)}"
EMAIL="${LE_EMAIL:-admin@${DOMAIN}}"

echo "==> RESTORE starting for ${SERVICE} on $(hostname) (domain: ${DOMAIN})"
export DEBIAN_FRONTEND=noninteractive

echo "==> Base packages"
apt-get update -y
apt-get install -y python3 python3-venv python3-pip nginx certbot python3-certbot-nginx ufw git curl

echo "==> Restoring HOME into $HOME"
tar -C "$HOME" -xzf "$WORKDIR/home/home.tar.gz"
chown -R "$SUDO_USER:$SUDO_USER" "$HOME" || true

echo "==> Restoring Nginx and TLS (if present)"
if [ -f "$WORKDIR/nginx/nginx.tar.gz" ]; then
  tar -xzf "$WORKDIR/nginx/nginx.tar.gz" -C /
fi
if [ -f "$WORKDIR/letsencrypt/letsencrypt.tar.gz" ]; then
  tar -xzf "$WORKDIR/letsencrypt/letsencrypt.tar.gz" -C /
  # Permissions sometimes reset; fix
  chown -R root:root /etc/letsencrypt || true
  chmod -R go-rwx /etc/letsencrypt || true
fi

echo "==> Restoring systemd unit templates (we’ll also (re)create the app unit)"
if [ -f "$WORKDIR/systemd/systemd_units.tar.gz" ]; then
  tar -xzf "$WORKDIR/systemd/systemd_units.tar.gz" -C /
fi

echo "==> App venv + deps"
mkdir -p "$APP_DIR"
cd "$APP_DIR"
python3 -m venv .venv
source .venv/bin/activate
if [ -d "$WORKDIR/wheels" ] && [ "$(ls -A "$WORKDIR/wheels")" ]; then
  pip install --no-index --find-links="$WORKDIR/wheels" -r "$APP_DIR/requirements.txt" || true
else
  [ -f "$APP_DIR/requirements.txt" ] && pip install -r "$APP_DIR/requirements.txt" || true
fi
deactivate

echo "==> Nginx vhost for ${DOMAIN} → 127.0.0.1:${APP_PORT}"
cat >/etc/nginx/sites-available/${SERVICE}.conf <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    client_max_body_size 20m;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/${SERVICE}.conf /etc/nginx/sites-enabled/${SERVICE}.conf
nginx -t && systemctl reload nginx

echo "==> TLS: issue if missing, otherwise keep restored certs"
if [ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
  certbot --nginx -d "${DOMAIN}" --redirect --agree-tos -m "${EMAIL}" --non-interactive || true
fi

echo "==> systemd service for ${SERVICE}"
cat >/etc/systemd/system/${SERVICE}.service <<SYS
[Unit]
Description=${SERVICE} app
After=network.target

[Service]
User=${SUDO_USER}
WorkingDirectory=${APP_DIR}
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=-${APP_DIR}/.env
ExecStart=${APP_DIR}/.venv/bin/python ${APP_DIR}/main.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SYS

systemctl daemon-reload
systemctl enable --now ${SERVICE}

echo "==> Firewall"
ufw allow OpenSSH || true
ufw allow 'Nginx Full' || true
ufw --force enable || true

echo "==> Crontabs"
if [ -f "$WORKDIR/crontab/root.cron" ]; then crontab -u root "$WORKDIR/crontab/root.cron" || true; fi
if [ -f "$WORKDIR/crontab/user.cron" ]; then crontab -u "$SUDO_USER" "$WORKDIR/crontab/user.cron" || true; fi

echo "==> Validate service & nginx"
systemctl --no-pager --full status ${SERVICE} || true
curl -I http://127.0.0.1:${APP_PORT} || true
nginx -t || true

echo "==> RESTORE finished. If domain already points here, try: https://${DOMAIN}"
RESTORESH
  chmod +x "$PAYLOAD/restore.sh"

  echo "==> Creating single-file bundle"
  BUNDLE="$HOME/${HOST}_oneclick_${NOW}.tgz"
  tar -C "$STAGE" -czf "$BUNDLE" payload
  echo "==> Backup complete."
  echo "Bundle: $BUNDLE"
  echo "Copy this file off the server. On new VM run:"
  echo "  bash oneclick.sh restore $BUNDLE"
}

### ----------- RESTORE (wrapper) -----------
restore_bundle() {
  local bundle="${1:-}"
  if [ -z "$bundle" ] || [ ! -f "$bundle" ]; then
    echo "Provide bundle: bash oneclick.sh restore /path/to/bundle.tgz"; exit 2
  fi
  need_root "$@"
  echo "==> Extracting $bundle"
  EXDIR="/tmp/oneclick_restore_${NOW}"
  mkdir -p "$EXDIR"
  tar -xzf "$bundle" -C "$EXDIR"
  bash "$EXDIR/payload/restore.sh"
}

### ----------- Main -----------
MODE="${1:-}"
case "$MODE" in
  backup)  backup ;;
  restore) shift; restore_bundle "${1:-}";;
  *) echo "Usage: bash oneclick.sh {backup|restore <bundle.tgz>}"; exit 1;;
esac
