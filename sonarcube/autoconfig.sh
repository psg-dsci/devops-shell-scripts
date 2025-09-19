set -euo pipefail

echo "[A] Remove broken Adoptium APT entry (plucky not supported)"
sudo rm -f /etc/apt/sources.list.d/adoptium.list /etc/apt/keyrings/adoptium.asc || true
sudo apt-get update -y

echo "[B] Install Java 21"
if ! (java -version 2>&1 | grep -q 'version "21'); then
  if ! sudo apt-get install -y openjdk-21-jdk; then
    echo "[B1] Ubuntu repo has no openjdk-21; fetching Temurin 21 tarball..."
    curl -fsSL -o /tmp/temurin21.tar.gz "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk?project=jdk"
    sudo rm -rf /opt/temurin-21
    sudo mkdir -p /opt/temurin-21
    sudo tar -xzf /tmp/temurin21.tar.gz -C /opt/temurin-21 --strip-components=1
    JAVA_HOME="/opt/temurin-21"
    echo "JAVA_HOME=${JAVA_HOME}"
  fi
fi
if [ -z "${JAVA_HOME:-}" ]; then
  # Prefer Temurin path if present; else use Debian alternatives path for OpenJDK
  if [ -x /opt/temurin-21/bin/java ]; then
    JAVA_HOME="/opt/temurin-21"
  else
    # try to auto-detect openjdk-21
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  fi
fi
"$JAVA_HOME/bin/java" -version

echo "[C] Ensure Postgres is running"
sudo apt-get install -y postgresql postgresql-contrib
sudo systemctl enable --now postgresql

echo "[D] Ensure SonarQube files exist (install if missing)"
if [ ! -d /opt/sonarqube ]; then
  SQV="${SONARQUBE_VERSION:-25.1.0.102122}"
  echo "[D1] Installing SonarQube ${SQV}"
  cd /tmp
  curl -fSL -o "sonarqube-${SQV}.zip" "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SQV}.zip"
  sudo unzip -q "sonarqube-${SQV}.zip" -d /opt
  sudo ln -sfn "/opt/sonarqube-${SQV}" /opt/sonarqube
fi

echo "[E] Kernel & limits (idempotent)"
echo -e "vm.max_map_count=524288\nfs.file-max=131072" | sudo tee /etc/sysctl.d/99-sonarqube.conf >/dev/null
sudo sysctl --system
sudo tee /etc/security/limits.d/99-sonarqube.conf >/dev/null <<'LIM'
sonar   -   nofile   131072
sonar   -   nproc     8192
LIM

echo "[F] Create sonar user and set permissions"
if ! getent group sonar >/dev/null; then sudo groupadd --system sonar; fi
if ! id -u sonar >/dev/null 2>&1; then
  sudo useradd --system --gid sonar --home /opt/sonarqube --shell /bin/bash sonar
fi
sudo chown -R sonar:sonar /opt/sonarqube* || true

echo "[G] DB config (reuse if present)"
sudo install -d -m 0750 /etc/sonarqube
if [ ! -f /etc/sonarqube/sonar-db.env ]; then
  DBPASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
  cat <<EOF | sudo tee /etc/sonarqube/sonar-db.env >/dev/null
SQ_DB_NAME=sonarqube
SQ_DB_USER=sonar
SQ_DB_PASS=${DBPASS}
EOF
  sudo -u postgres psql <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname='sonarqube') THEN CREATE DATABASE sonarqube; END IF;
END\$\$;
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='sonar') THEN CREATE USER sonar WITH ENCRYPTED PASSWORD '${DBPASS}'; END IF;
END\$\$;
GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonar;
ALTER DATABASE sonarqube OWNER TO sonar;
SQL
fi
set -a; source /etc/sonarqube/sonar-db.env; set +a

echo "[H] Write sonar.properties (bind localhost; NGINX proxies :80 -> :9000)"
sudo sed -i '/^sonar.jdbc.url=/d;/^sonar.jdbc.username=/d;/^sonar.jdbc.password=/d;/^sonar.web.host=/d;/^sonar.web.port=/d' /opt/sonarqube/conf/sonar.properties || true
sudo tee -a /opt/sonarqube/conf/sonar.properties >/dev/null <<PROP

# --- Managed ---
sonar.jdbc.url=jdbc:postgresql://127.0.0.1:5432/${SQ_DB_NAME}
sonar.jdbc.username=${SQ_DB_USER}
sonar.jdbc.password=${SQ_DB_PASS}
sonar.web.host=127.0.0.1
sonar.web.port=9000
PROP
sudo chown sonar:sonar /opt/sonarqube/conf/sonar.properties

echo "[I] Create/refresh systemd unit with JAVA_HOME"
sudo tee /etc/systemd/system/sonarqube.service >/dev/null <<UNIT
[Unit]
Description=SonarQube service
After=network.target postgresql.service
Wants=network-online.target

[Service]
Type=forking
User=sonar
Group=sonar
LimitNOFILE=131072
LimitNPROC=8192
Environment=JAVA_HOME=${JAVA_HOME}
WorkingDirectory=/opt/sonarqube
ExecStart=/bin/bash /opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/bin/bash /opt/sonarqube/bin/linux-x86-64/sonar.sh stop
Restart=on-failure
TimeoutSec=600

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable sonarqube
sudo systemctl start sonarqube

echo "[J] Wait for health"
for i in {1..70}; do
  if curl -fsS http://127.0.0.1:9000/api/system/health | grep -q '"status":"UP"'; then
    echo "✅ SonarQube is UP"
    break
  fi
  sleep 6
  if (( i % 10 == 0 )); then
    echo "--- sonar.log tail ---"; sudo tail -n 40 /opt/sonarqube/logs/sonar.log || true
  fi
done

echo "Hit Sonar at: http://$(curl -s ifconfig.me)/  (Jenkins at /jenkins)"
sudo ss -ltnp | egrep ':80|:9000|:8080' || true
