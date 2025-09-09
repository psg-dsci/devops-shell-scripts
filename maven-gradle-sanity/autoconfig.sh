#!/usr/bin/env bash
# install_java_env_universal.sh
# Universal, fail-safe Java dev autoconfig:
# - Detects distro/WSL
# - Installs JDK 17, Maven, zip/unzip, curl, CA certs
# - Installs Gradle via SDKMAN! (auto-yes), falls back to package manager
# - Sets JAVA_HOME idempotently
# - Creates & tests Maven/Gradle sample projects (quiet)
# - Prints SUCCESS/FAIL summary and writes a full log

set -o pipefail
export DEBIAN_FRONTEND=noninteractive

START_TS="$(date +%Y%m%d_%H%M%S)"
LOG="$HOME/java_setup_${START_TS}.log"
touch "$LOG"

FAILED_STEPS=()
FAIL_COUNT=0

# ---------- helpers ----------
say() { printf "%-68s" "• $1"; }
ok()  { echo "[OK]"; }
no()  { echo "[FAIL]"; FAILED_STEPS+=("$1"); FAIL_COUNT=$((FAIL_COUNT+1)); }
section() { echo -e "\n=== $1 ===" | tee -a "$LOG"; }
run() {
  local DESC="$1"; shift
  say "$DESC"
  bash -lc "$*" >>"$LOG" 2>&1
  local RC=$?
  if [ $RC -eq 0 ]; then ok; else no "$DESC"; fi
  return $RC
}
append_once() { local LINE="$1" FILE="$2"; grep -qxF "$LINE" "$FILE" 2>/dev/null || echo "$LINE" >> "$FILE"; }

is_wsl() {
  grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null && return 0 || return 1
}

have() { command -v "$1" >/dev/null 2>&1; }

pm_detect() {
  # Sets globals: PM, PM_INSTALL, PM_UPDATE, PM_GROUPINSTALL (optional)
  if have apt-get; then
    PM="apt"
    PM_UPDATE="sudo apt-get -y -qq update"
    PM_INSTALL="sudo apt-get -y -qq install"
  elif have dnf; then
    PM="dnf"
    PM_UPDATE="sudo dnf -y -q makecache"
    PM_INSTALL="sudo dnf -y -q install"
  elif have yum; then
    PM="yum"
    PM_UPDATE="sudo yum -y -q makecache"
    PM_INSTALL="sudo yum -y -q install"
  elif have zypper; then
    PM="zypper"
    PM_UPDATE="sudo zypper --quiet --non-interactive refresh"
    PM_INSTALL="sudo zypper --quiet --non-interactive install -y"
  elif have apk; then
    PM="apk"
    PM_UPDATE="sudo apk update  >/dev/null"
    PM_INSTALL="sudo apk add --no-progress --quiet"
  elif have pacman; then
    PM="pacman"
    PM_UPDATE="sudo pacman -Sy --noconfirm --quiet"
    PM_INSTALL="sudo pacman -S --noconfirm --quiet"
  else
    PM="unknown"
  fi
}

pkg_installed() {
  local pkg="$1"
  case "$PM" in
    apt)   dpkg -s "$pkg" >/dev/null 2>&1 ;;
    dnf|yum|zypper) rpm -q "$pkg" >/dev/null 2>&1 ;;
    apk)   apk info -e "$pkg" >/dev/null 2>&1 ;;
    pacman) pacman -Qi "$pkg" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

pm_try_install() {
  # tries to install all given packages; ignores those already present
  local pkgs=()
  for p in "$@"; do
    if [ -n "$p" ]; then pkgs+=("$p"); fi
  done
  [ ${#pkgs[@]} -eq 0 ] && return 0

  case "$PM" in
    apt)
      run "APT update" "$PM_UPDATE"
      run "Install: ${pkgs[*]}" "$PM_INSTALL ${pkgs[*]}"
      ;;
    dnf|yum)
      run "Makecache (${PM^^})" "$PM_UPDATE"
      run "Install: ${pkgs[*]}" "$PM_INSTALL ${pkgs[*]}"
      ;;
    zypper|apk|pacman)
      run "Refresh (${PM^^})" "$PM_UPDATE"
      run "Install: ${pkgs[*]}" "$PM_INSTALL ${pkgs[*]}"
      ;;
    *)
      no "Package install (${PM})"
      ;;
  esac
}

# ---------- preflight ----------
echo "== Universal Java Dev Installer (quiet, fail-safe) =="
echo "Log: $LOG"
echo

is_wsl && echo "(Detected WSL)" | tee -a "$LOG"

# SUDO shim (run as root if no sudo)
if have sudo; then SUDO=sudo; else SUDO=""; fi

# OS release info
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DIST_ID="${ID:-unknown}"
  DIST_VER="${VERSION_ID:-unknown}"
else
  DIST_ID="unknown"; DIST_VER="unknown"
fi

pm_detect
echo "Detected: ID=$DIST_ID VER=$DIST_VER PM=$PM" | tee -a "$LOG"

# ---------- base tools ----------
section "Base tooling"
pm_try_install ca-certificates curl zip unzip tar gzip

# ---------- JDK + Maven ----------
section "JDK + Maven"
JDK_PKG=""
MAVEN_PKG="maven"

case "$PM:$DIST_ID:$DIST_VER" in
  apt:*)
    JDK_PKG="openjdk-17-jdk"
    ;;
  dnf:amzn:2023|dnf:amzn:*)
    # Amazon Linux (prefer Corretto; fallback to OpenJDK)
    if run "Install Corretto 17 (AL)" "sudo dnf -y -q install java-17-amazon-corretto-devel"; then
      JDK_PKG=""
    else
      JDK_PKG="java-17-openjdk-devel"
    fi
    ;;
  yum:amzn:2)
    # Amazon Linux 2: try corretto repo first, then openjdk
    if run "Install Corretto 17 repo (AL2)" "sudo rpm --quiet -Uvh https://rpm.corretto.aws/corretto.repo"; then
      if run "Install Corretto 17 (AL2)" "sudo yum -y -q install java-17-amazon-corretto-devel"; then
        JDK_PKG=""
      else
        JDK_PKG="java-17-openjdk-devel"
      fi
    else
      JDK_PKG="java-17-openjdk-devel"
    fi
    ;;
  dnf:*)
    JDK_PKG="java-17-openjdk-devel"
    ;;
  yum:*)
    JDK_PKG="java-17-openjdk-devel"
    ;;
  zypper:*)
    JDK_PKG="java-17-openjdk-devel"
    ;;
  apk:*)
    # Alpine package names
    JDK_PKG="openjdk17"
    MAVEN_PKG="maven"
    ;;
  pacman:*)
    JDK_PKG="jdk17-openjdk"
    MAVEN_PKG="maven"
    ;;
  *:*)
    JDK_PKG="openjdk-17-jdk"
    ;;
esac

# Install JDK if still needed
if [ -n "$JDK_PKG" ]; then
  pm_try_install "$JDK_PKG"
fi

# Install Maven
pm_try_install "$MAVEN_PKG"

# ---------- SDKMAN + Gradle ----------
section "Gradle via SDKMAN (fallback to package)"
SDKMAN_DIR="$HOME/.sdkman"

# Ensure shell rc exists for later idempotent PATH
touch "$HOME/.bashrc"

# Install SDKMAN
if run "Install SDKMAN!" 'curl -s "https://get.sdkman.io" | bash'; then
  run "Init SDKMAN" 'source "$HOME/.sdkman/bin/sdkman-init.sh"'
  # auto-yes & silent
  run "SDKMAN auto-yes" 'mkdir -p "$HOME/.sdkman/etc"; echo "sdkman_auto_answer=true" > "$HOME/.sdkman/etc/config"'
  # install gradle quietly
  if run "Install Gradle (SDKMAN)" 'source "$HOME/.sdkman/bin/sdkman-init.sh" && yes | sdk install gradle >/dev/null'; then
    :
  else
    # fallback to package manager
    case "$PM" in
      apt)   pm_try_install gradle ;;
      dnf)   pm_try_install gradle ;;
      yum)   pm_try_install gradle ;;
      zypper) pm_try_install gradle ;;
      apk)   pm_try_install gradle ;;
      pacman) pm_try_install gradle ;;
    esac
  fi
else
  # SDKMAN failed entirely, fallback to PM Gradle
  case "$PM" in
    apt|dnf|yum|zypper|apk|pacman) pm_try_install gradle ;;
  esac
fi

# ---------- JAVA_HOME ----------
section "JAVA_HOME"
say "Configure JAVA_HOME"
JAVA_BIN="$(command -v java || true)"
JAVA_HOME_CALC=""
if [ -n "$JAVA_BIN" ]; then
  JAVA_HOME_CALC="$(dirname "$(dirname "$(readlink -f "$JAVA_BIN")")")"
fi
if [ -n "$JAVA_HOME_CALC" ] && [ -d "$JAVA_HOME_CALC" ]; then
  export JAVA_HOME="$JAVA_HOME_CALC"
  append_once "export JAVA_HOME=\"$JAVA_HOME_CALC\"" "$HOME/.bashrc"
  append_once 'export PATH="$JAVA_HOME/bin:$PATH"' "$HOME/.bashrc"
  ok
else
  no "Configure JAVA_HOME"
fi

# ---------- Versions ----------
section "Versions"
run "java -version" "java -version"
run "mvn -v (quiet)" "mvn -q -v"
if have gradle; then
  run "gradle -v (quiet)" "gradle -q -v"
else
  no "gradle present"
fi

# ---------- Smoke tests ----------
section "Smoke tests"
DEVROOT="$HOME/dev"
MVN_DIR="$DEVROOT/demo-mvn"
GRADLE_DIR="$DEVROOT/demo-gradle"

run "Create Maven project" "mkdir -p '$DEVROOT' && cd '$DEVROOT' && rm -rf '$MVN_DIR' && mvn -B -q archetype:generate -DgroupId=com.example -DartifactId=demo-mvn -DarchetypeArtifactId=maven-archetype-quickstart -DarchetypeVersion=1.4"
run "Run Maven tests"     "cd '$MVN_DIR' && mvn -q test"

if have gradle; then
  run "Create Gradle project" "mkdir -p '$DEVROOT' && cd '$DEVROOT' && rm -rf '$GRADLE_DIR' && gradle -q init --type java-application --dsl kotlin --test-framework junit --project-name demo-gradle --package com.example.app --no-scan"
  run "Run Gradle tests" "cd '$GRADLE_DIR' && chmod +x gradlew && ./gradlew -q test"
else
  no "Gradle sample (gradle not installed)"
fi

# ---------- WSL niceties ----------
if is_wsl; then
  section "WSL notes"
  echo "WSL detected: using distro package manager. No extra steps required." >> "$LOG"
fi

# ---------- summary ----------
echo
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "✅ SUCCESS — Java 17, Maven, Gradle installed & verified. Log: $LOG"
  exit 0
else
  echo "❌ FAIL — $FAIL_COUNT step(s) failed:"
  for s in "${FAILED_STEPS[@]}"; do echo "   - $s"; done
  echo "See detailed log: $LOG"
  exit 1
fi
