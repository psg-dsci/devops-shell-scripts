#!/usr/bin/env bash
# install_java_env.sh — Java + Maven + Gradle (quiet, no prompts), with smoke tests.
# Works on Ubuntu/WSL. Creates a log and prints final SUCCESS/FAIL.

set -o pipefail
export DEBIAN_FRONTEND=noninteractive

LOG="$HOME/java_setup_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG"

FAILED_STEPS=()
FAIL_COUNT=0

say() { printf "%-55s" "• $1"; }
ok()  { echo "[OK]"; }
no()  { echo "[FAIL]"; FAILED_STEPS+=("$1"); FAIL_COUNT=$((FAIL_COUNT+1)); }

run() {
  local DESC="$1"; shift
  say "$DESC"
  bash -lc "$*" >>"$LOG" 2>&1
  local RC=$?
  if [ $RC -eq 0 ]; then ok; else no "$DESC"; fi
  return $RC
}

append_once() { # append line to file only if missing
  local LINE="$1" FILE="$2"
  grep -qxF "$LINE" "$FILE" 2>/dev/null || echo "$LINE" >> "$FILE"
}

echo "== Java Dev Environment Installer (quiet mode) =="
echo "Log: $LOG"
echo

# 0) Refresh & base packages
run "Apt update"              "sudo apt-get -y -qq update"
run "Apt upgrade"             "sudo apt-get -y -qq upgrade"
run "Install base packages"   "sudo apt-get -y -qq install openjdk-17-jdk maven curl zip unzip ca-certificates"

# 1) Configure JAVA_HOME (idempotent)
say "Configure JAVA_HOME"
JAVA_HOME_CALC="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
if [ -n "$JAVA_HOME_CALC" ] && [ -d "$JAVA_HOME_CALC" ]; then
  export JAVA_HOME="$JAVA_HOME_CALC"
  append_once "export JAVA_HOME=\"$JAVA_HOME_CALC\"" "$HOME/.bashrc"
  append_once 'export PATH="$JAVA_HOME/bin:$PATH"' "$HOME/.bashrc"
  ok
else
  no "Configure JAVA_HOME"
fi

# 2) SDKMAN (quiet + auto-yes) and Gradle
run "Install SDKMAN"          'curl -s "https://get.sdkman.io" | bash'
run "Initialize SDKMAN"       'source "$HOME/.sdkman/bin/sdkman-init.sh"'
run "Enable SDKMAN auto-yes"  'mkdir -p "$HOME/.sdkman/etc"; append_once "sdkman_auto_answer=true" "$HOME/.sdkman/etc/config"'
# Try latest Gradle via SDKMAN (auto-yes); fall back to apt if needed
run "Install Gradle (SDKMAN)" 'source "$HOME/.sdkman/bin/sdkman-init.sh" && yes | sdk install gradle >/dev/null'
if ! command -v gradle >/dev/null 2>&1; then
  run "Install Gradle (apt fallback)" "sudo apt-get -y -qq install gradle"
fi

# 3) Versions (logged)
run "Check Java version"      "java -version"
run "Check Maven version"     "mvn -q -v"
run "Check Gradle version"    "gradle -q -v"

# 4) Smoke tests (quiet)
DEVROOT="$HOME/dev"
run "Create Maven sample"     "mkdir -p '$DEVROOT' && cd '$DEVROOT' && rm -rf demo-mvn && mvn -B -q archetype:generate -DgroupId=com.example -DartifactId=demo-mvn -DarchetypeArtifactId=maven-archetype-quickstart -DarchetypeVersion=1.4"
run "Run Maven tests"         "cd '$DEVROOT'/demo-mvn && mvn -q test"

run "Create Gradle sample"    "mkdir -p '$DEVROOT' && cd '$DEVROOT' && rm -rf demo-gradle && gradle -q init --type java-application --dsl kotlin --test-framework junit --project-name demo-gradle --package com.example.app --no-scan"
run "Run Gradle tests"        "cd '$DEVROOT'/demo-gradle && chmod +x gradlew && ./gradlew -q test"

echo
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "SUCCESS — Java 17, Maven, Gradle installed and verified. See log: $LOG"
  exit 0
else
  echo "FAIL — $FAIL_COUNT step(s) failed:"
  for s in "${FAILED_STEPS[@]}"; do echo "   - $s"; done
  echo "Check log for details: $LOG"
  exit 1
fi
