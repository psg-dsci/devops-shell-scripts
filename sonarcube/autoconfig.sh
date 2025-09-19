#!/usr/bin/env bash
set -euo pipefail

### --- CONFIG (override via env) ---
# Known-good version (Jan 2025 LTA line) – override with SONARQUBE_VERSION=25.4.0.105899, etc.
SONARQUBE_VERSION="${SONARQUBE_VERSION:-25.1.0.102122}"
SONARQUBE_ZIP="sonarqube-${SONARQUBE_VERSION}.zip"
SONARQUBE_URL="${SONARQUBE_URL:-https://binaries.sonarsource.com/Distribution/sonarqube/${SONARQUBE_ZIP}}"

# DB settings
SQ_DB_NAME="${SQ_DB_NAME:-sonarqube}"
SQ_DB_USER="${SQ_DB_USER:-sonar}"
SQ_DB_PASS="${SQ_DB_PASS:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)}"

# Paths
SQ_HOME_BASE="/opt"
SQ_DIR_LINK="${SQ_HOME_BASE}/sonarqube"
SQ_DIR_VER="${SQ_HOME_BASE}/sonarqube-${SONARQUBE_VERSION}"
SQ_USER="sonar"
SQ_GROUP="sonar"

echo "[INFO] Updating apt and installing base packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget unzip gnupg2 ca-certificates lsb-release apt-transport-https jq

echo "[INFO] Installing Java (try OpenJDK 21, fallback to 17 if needed)..."
if ! apt-get install -y openjdk-21-jdk; then
  echo "[WARN] openjdk-21-jdk not available, installing openjdk-17-jdk..."
  apt-get install -y openjdk-17-jdk
fi

JAVA_BIN="$(command -v java)"
echo "[INFO] Java at: ${JAVA_BIN}"
"${JAVA_BIN}" -version || true

echo "[INFO] Installing PostgreSQL..."
apt-get install -y postgresql postgresql-contrib

echo "[INFO] Creating SonarQube database and user..."
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${SQ_DB_NAME}') THEN
      CREATE DATABASE ${SQ_DB_NAME};
   END IF;
END
\$\$;
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${SQ_DB_USER}') THEN
      CREATE USER ${SQ_DB_USER} WITH ENCRYPTED PASSWORD '${SQ_DB_PASS}';
   END IF;
END
\$\$;
GRANT ALL PRIVILEGES ON DATABASE ${SQ_DB_NAME} TO ${SQ_DB_USER};
ALTER DATABASE ${SQ_DB_NAME} OWNER TO ${SQ_DB_USER};
SQL

echo "[INFO] Saving DB credentials to /etc/sonarqube/sonar-db.env (root-only)..."
install -d -m 0750 /etc/sonarqube
cat >/etc/sonarqube/sonar-db.env <<ENV
SQ_DB_NAME=${SQ_DB_NAME}
SQ_DB_USER=${SQ_DB_USER}
SQ_DB_PASS=${SQ_DB_PASS}
ENV
chmod 0640 /etc/sonarqube/sonar-db.env

echo "[INFO] Creating sonar user/group and directories..."
id -u "${SQ_USER}" &>/dev/null || useradd --system --home "${SQ_DIR_LINK}" --shell /bin/bash --gid nogroup "${SQ_USER}"
groupmod -n "${SQ_GROUP}" nogroup || true

echo "[INFO] Downloading SonarQube ${SONARQUBE_VERSION}..."
cd /tmp
rm -f "${SONARQUBE_ZIP}"
wget -q "${SONARQUBE_URL}"

echo "[INFO] Unpacking to ${SQ_DIR_VER} and linking ${SQ_DIR_LINK}..."
rm -rf "${SQ_DIR_VER}" "${SQ_DIR_LINK}"
unzip -q "${SONARQUBE_ZIP}" -d "${SQ_HOME_BASE}"
mv "${SQ_HOME_BASE}/sonarqube-${SONARQUBE_VERSION}" "${SQ_DIR_VER}"
ln -s "${SQ_DIR_VER}" "${SQ_DIR_LINK}"

echo "[INFO] Setting kernel & ulimit requirements for Elasticsearch..."
# Official requirements: vm.max_map_count >= 524288, fs.file-max >= 131072; nofile >= 131072, nproc >= 8192
cat >/etc/sysctl.d/99-sonarqube.conf <<SYS
vm.max_map_count=524288
fs.file-max=131072
SYS
sysctl --system

cat >/etc/security/limits.d/99-sonarqube.conf <<LIM
${SQ_USER}   -   nofile   131072
${SQ_USER}   -   nproc     8192
LIM

echo "[INFO] Configuring sonar.properties..."
JDBC_URL="jdbc:postgresql://127.0.0.1:5432/${SQ_DB_NAME}"
sed -i 's|^#\(sonar.jdbc.username=\).*|\1|g' "${SQ_DIR_LINK}/conf/sonar.properties" || true
sed -i 's|^#\(sonar.jdbc.password=\).*|\1|g' "${SQ_DIR_LINK}/conf/sonar.properties" || true
sed -i 's|^#\(sonar.jdbc.url=\).*|\1|g'       "${SQ_DIR_LINK}/conf/sonar.properties" || true

# Append (idempotent guard)
grep -q "^sonar.jdbc.url=" "${SQ_DIR_LINK}/conf/sonar.properties" || true
cat >>"${SQ_DIR_LINK}/conf/sonar.properties" <<PROP

# --- Managed by one-click installer ---
sonar.jdbc.url=${JDBC_URL}
sonar.jdbc.username=${SQ_DB_USER}
sonar.jdbc.password=${SQ_DB_PASS}

# Bind only to localhost; NGINX will proxy from :80
sonar.web.host=127.0.0.1
sonar.web.port=9000

# JVM opts can be tuned; defaults are usually fine on small VMs
#sonar.search.javaOpts=-Xms512m -Xmx512m -XX:+UseG1GC
PROP

echo "[INFO] Permissions..."
chown -R "${SQ_USER}:${SQ_GROUP}" "${SQ_DIR_VER}"
chown -h "${SQ_USER}:${SQ_GROUP}" "${SQ_DIR_LINK}"

echo "[INFO] Creating systemd service..."
cat >/etc/systemd/system/sonarqube.service <<'UNIT'
[Unit]
Description=SonarQube service
After=network.target syslog.target postgresql.service
Wants=network-online.target

[Service]
Type=forking
User=sonar
Group=sonar
# Ensure limits meet docs requirements
LimitNOFILE=131072
LimitNPROC=8192
EnvironmentFile=-/etc/sonarqube/sonar-db.env
WorkingDirectory=/opt/sonarqube
ExecStart=/bin/bash /opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/bin/bash /opt/sonarqube/bin/linux-x86-64/sonar.sh stop
Restart=on-failure
TimeoutSec=600
# Give the process ability to allocate mmaps; relies on sysctl set above

[Install]
WantedBy=multi-user.target
UNIT

echo "[INFO] Installing and configuring NGINX reverse proxy (:80 -> 127.0.0.1:9000)..."
apt-get install -y nginx
cat >/etc/nginx/sites-available/sonarqube <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    client_max_body_size 50M;
    location / {
        proxy_pass         http://127.0.0.1:9000;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_read_timeout 600s;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
    }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/sonarqube /etc/nginx/sites-enabled/sonarqube
nginx -t && systemctl enable --now nginx

echo "[INFO] Enabling and starting SonarQube..."
systemctl daemon-reload
systemctl enable postgresql
systemctl enable sonarqube
systemctl start sonarqube

echo "[INFO] Waiting for SonarQube health (this can take ~1-3 minutes on small VMs)..."
# Wait up to ~7 minutes for full Elasticsearch bootstrap on tiny machines
ATTEMPTS=70
until curl -fsS http://127.0.0.1:9000/api/system/health | grep -q '"status":"UP"'; do
  ATTEMPTS=$((ATTEMPTS-1)) || true
  if [ $ATTEMPTS -le 0 ]; then
    echo "[WARN] Health check timed out. Check logs: /opt/sonarqube/logs/sonar.log"
    break
  fi
  sleep 6
done

echo
echo "==============================================================="
echo " ✅ SonarQube installed."
echo "    URL  : http://<this-VM-external-IP>/"
echo "    Local: http://127.0.0.1:9000/ (proxied to :80)"
echo "    Login: admin / admin   (you'll be asked to change it)"
echo
echo " DB: ${SQ_DB_NAME}  User: ${SQ_DB_USER}  Pass: ${SQ_DB_PASS}"
echo "    (also stored at /etc/sonarqube/sonar-db.env)"
echo
echo " Logs:  /opt/sonarqube/logs/*.log"
echo " Service cmds:  systemctl status|start|stop sonarqube"
echo
echo " NOTE (GCP): Ensure your VPC firewall allows TCP/80 to this VM."
echo "==============================================================="
