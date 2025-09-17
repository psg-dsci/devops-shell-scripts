#!/usr/bin/env bash
# Jenkins + Nginx (port 80) installer for Ubuntu/Debian
# Usage:
#   sudo bash jenkins_nginx_install.sh
# Optional env vars:
#   DOMAIN=ci.example.com  (used in nginx server_name; defaults to _)
set -euo pipefail

DOMAIN="${DOMAIN:-_}"   # nginx server_name; "_" matches any host
JENKINS_LISTEN_IP="127.0.0.1"
JENKINS_PORT="8080"
DEBIAN_FRONTEND=noninteractive

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (e.g., sudo bash $0)"; exit 1
  fi
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    ID="${ID:-}"; VERSION_CODENAME="${VERSION_CODENAME:-}"
  else
    echo "Cannot detect OS. /etc/os-release missing."; exit 1
  fi
  case "$ID" in
    ubuntu|debian) : ;;
    *)
      echo "This script supports Ubuntu/Debian. Detected: $ID"; exit 1
      ;;
  esac
}

apt_update_base() {
  apt-get update -y
  apt-get install -y --no-install-recommends curl gnupg ca-certificates \
    apt-transport-https software-properties-common
}

install_java() {
  # Jenkins LTS supports Java 17; install headless JRE
  apt-get install -y openjdk-17-jre-headless
}

install_jenkins() {
  # Add Jenkins repo (debian-stable)
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
    -o /etc/apt/keyrings/jenkins-key.asc
  chmod 0644 /etc/apt/keyrings/jenkins-key.asc

  if ! grep -q "pkg.jenkins.io/debian-stable" /etc/apt/sources.list.d/jenkins.list 2>/dev/null; then
    echo "deb [signed-by=/etc/apt/keyrings/jenkins-key.asc] https://pkg.jenkins.io/debian-stable binary/" \
      > /etc/apt/sources.list.d/jenkins.list
  fi

  apt-get update -y
  apt-get install -y jenkins
}

configure_jenkins_bind() {
  # On Debian/Ubuntu package, /etc/default/jenkins controls listen/port.
  # Ensure it listens only on 127.0.0.1 and the desired port.
  if [[ -f /etc/default/jenkins ]]; then
    sed -i "s|^HTTP_PORT=.*|HTTP_PORT=${JENKINS_PORT}|g" /etc/default/jenkins || true
    # Add/replace JENKINS_LISTEN_ADDRESS or JENKINS_ARGS with --httpListenAddress
    if grep -q "^JENKINS_LISTEN_ADDRESS=" /etc/default/jenkins; then
      sed -i "s|^JENKINS_LISTEN_ADDRESS=.*|JENKINS_LISTEN_ADDRESS=${JENKINS_LISTEN_IP}|g" /etc/default/jenkins
    else
      echo "JENKINS_LISTEN_ADDRESS=${JENKINS_LISTEN_IP}" >> /etc/default/jenkins
    fi

    # Ensure systemd honors address; recent packages read LISTEN_ADDRESS
    # Also set JENKINS_ARGS defensively for older templates
    if grep -q "^JENKINS_ARGS=" /etc/default/jenkins; then
      sed -i "s|^JENKINS_ARGS=.*|JENKINS_ARGS=\"--httpListenAddress=${JENKINS_LISTEN_IP} --httpPort=${JENKINS_PORT}\"|g" /etc/default/jenkins
    else
      echo "JENKINS_ARGS=\"--httpListenAddress=${JENKINS_LISTEN_IP} --httpPort=${JENKINS_PORT}\"" >> /etc/default/jenkins
    fi
  else
    echo "/etc/default/jenkins not found; package layout changed?"; exit 1
  fi
}

install_nginx() {
  apt-get install -y nginx
  systemctl enable nginx
}

configure_nginx_site() {
  local site_conf="/etc/nginx/sites-available/jenkins"
  cat > "$site_conf" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    # Optional: increase client body for plugin uploads
    client_max_body_size 100m;

    # Forward all requests to Jenkins
    location / {
        proxy_pass http://${JENKINS_LISTEN_IP}:${JENKINS_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Upgrade WebSocket connections used by some plugins
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 90;
        proxy_redirect off;
    }
}
EOF

  ln -sf "$site_conf" /etc/nginx/sites-enabled/jenkins
  # Disable default site if present to avoid conflicts
  if [[ -e /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default
  fi

  nginx -t
  systemctl restart nginx
}

open_firewall_if_ufw() {
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "Nginx Full" || true
  fi
}

start_enable_jenkins() {
  systemctl daemon-reload
  systemctl enable jenkins
  systemctl restart jenkins
}

show_initial_password() {
  echo "Waiting for Jenkins to initialize (first start may take ~30–60s)..."
  # Try a few times to read initial password
  for i in {1..30}; do
    if [[ -s /var/lib/jenkins/secrets/initialAdminPassword ]]; then
      echo
      echo "======== Jenkins is up! ========"
      echo "Open: http://$(hostname -I | awk '{print $1}')/  (or http://${DOMAIN}/ if DNS points here)"
      echo -n "Initial Admin Password: "
      cat /var/lib/jenkins/secrets/initialAdminPassword
      echo
      return 0
    fi
    sleep 2
  done

  echo
  echo "Jenkins started, but the initial password wasn't ready."
  echo "You can fetch it manually with:"
  echo "  sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
}

main() {
  require_root
  detect_os
  apt_update_base
  install_java
  install_jenkins
  configure_jenkins_bind
  install_nginx
  configure_nginx_site
  open_firewall_if_ufw
  start_enable_jenkins
  show_initial_password
}

main "$@"
