#!/usr/bin/env bash
# auto.sh — Universal, fail-safe Java dev autoconfig
# - Self-relocates to $HOME/.autoconfig if launched from /mnt/* or unsafe paths
# - Detects distro/WSL
# - Pre-auths sudo once; uses sudo -n afterward; keeps ticket alive
# - Installs: JDK 17, Maven, zip/unzip, curl, CA certs, Gradle (SDKMAN; PM fallback)
# - Sets JAVA_HOME idempotently
# - Creates & tests Maven/Gradle sample projects (quiet)
# - Retries installs; recovers common apt lock/partial-config states
# - Logs everything; prints SUCCESS/FAIL summary
set -o pipefail
# Prevent job-control/TTOU/TTIN suspends & make steps time-bounded
set +m
trap '' SIGTTOU SIGTTIN SIGTSTP

# Default per-step timeout in seconds (can override: STEP_TIMEOUT=300 bash auto.sh)
STEP_TIMEOUT="${STEP_TIMEOUT:-180}"

# If 'timeout' exists, wrap steps with it
RUN_WRAP=""
if command -v timeout >/dev/null 2>&1; then
  RUN_WRAP="timeout -k 5 ${STEP_TIMEOUT}"
fi

# ---- Require sudo early ----
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This installer needs elevated privileges."
  echo "Run: sudo bash \"$0\" $*"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

START_TS="$(date +%Y%m%d_%H%M%S)"
LOG="$HOME/java_setup_${START_TS}.log"

# ---- Debug toggle & xtrace to LOG ----
DEBUG=${AUTO_DEBUG:-0}
if [[ "${1:-}" == "--debug" ]]; then DEBUG=1; shift; fi

# ---- Optional fast path: only run Python tests (private flag) ----
# Usage: sudo bash "$0" --python-only [--debug]
PY_ONLY=0
case "${1:-}" in
  --python-only|--only-python)
    PY_ONLY=1
    export AUTO_ONLY_PY=1   # preserve across self-relocate
    shift
    ;;
esac


# Pretty PS4 with timestamp, pid, file:line, function
export PS4='+ [${EPOCHREALTIME}] [$$] ${BASH_SOURCE##*/}:${LINENO} ${FUNCNAME[0]:-main}() : '

if (( DEBUG )); then
  # xtrace for the parent script goes to FD 9, which we point at $LOG
  exec 9>>"$LOG"
  export BASH_XTRACEFD=9
  set -x
  echo "DEBUG MODE ON: verbose xtrace enabled" | tee -a "$LOG"
fi

# [ADD] Put this block right after the DEBUG block (before FAILED_STEPS)
# ---- Color palette (TTY-aware; disable with NO_COLOR=1) ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
  BLUE=$'\033[38;5;39m'; CYAN=$'\033[36m'
  GREEN=$'\033[38;5;82m'; YELLOW=$'\033[38;5;214m'
  RED=$'\033[38;5;196m'; GRAY=$'\033[38;5;245m'
else
  RESET=; BOLD=; DIM=; BLUE=; CYAN=; GREEN=; YELLOW=; RED=; GRAY=
fi
OK_BR="${GRAY}[${RESET}${GREEN}OK${RESET}${GRAY}]${RESET}"
FAIL_BR="${GRAY}[${RESET}${RED}FAIL${RESET}${GRAY}]${RESET}"


FAILED_STEPS=()
FAIL_COUNT=0

say() { printf "%-70s" "• $1"; }
ok()  { echo -e "${OK_BR}"; }
no()  { echo -e "${FAIL_BR}"; FAILED_STEPS+=("$1"); FAIL_COUNT=$((FAIL_COUNT+1)); }
section(){ echo -e "\n${BOLD}${BLUE}=== $1 ===${RESET}" | tee -a "$LOG"; }
have(){ command -v "$1" >/dev/null 2>&1; }
is_wsl(){ grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null; }
append_once(){ local L="$1" F="$2"; grep -qxF "$L" "$F" 2>/dev/null || echo "$L" >> "$F"; }
# Portable "readlink -f"
rlf() {
  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$1" 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY' || true
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
    return 0
  fi
  # fallback: best-effort
  printf "%s" "$1"
}


# Always load ~/.bashrc in subshell so SDKMAN PATH is visible
# Always run steps in a non-interactive shell, no stdin, with timeout if available
run() {
  local DESC="$1"; shift
  local CMD="$*"
  say "$DESC"

  {
    echo "----- BEGIN STEP: $DESC -----"
    echo "CMD: $CMD"
  } >>"$LOG"

  local RC
  if (( DEBUG )); then
    # xtrace into LOG only
    $RUN_WRAP bash -lc "export PS4='$PS4'; export BASH_XTRACEFD=2; set -o pipefail; set -x; $CMD" >>"$LOG" 2>&1 < /dev/null
    RC=$?
  else
    $RUN_WRAP bash -lc "$CMD" >>"$LOG" 2>&1 < /dev/null
    RC=$?
  fi

  echo "RC: $RC" >>"$LOG"
  echo "----- END STEP: $DESC -----" >>"$LOG"

  if [ $RC -eq 0 ]; then ok; else no "$DESC"; fi
  return $RC
}



diag() {
  {
    echo
    echo "==== DIAGNOSTICS SNAPSHOT ===="
    echo "whoami: $(whoami)"
    echo "pwd: $(pwd)"
    echo "shell: $SHELL"
    echo "PATH: $PATH"
    echo
    echo "which java: $(command -v java || echo 'N/A')"
    echo "which mvn : $(command -v mvn  || echo 'N/A')"
    echo "which gradle: $(command -v gradle || echo 'N/A')"
    echo
    echo "SDKMAN dir: $HOME/.sdkman"
    ls -l "$HOME/.sdkman" 2>/dev/null || true
    echo
    echo "Gradle candidates:"
    ls -l "$HOME/.sdkman/candidates/gradle" 2>/dev/null || true
    echo
    echo "Gradle 'current' link:"
    ls -l "$HOME/.sdkman/candidates/gradle/current" 2>/dev/null || true
    echo
    echo "Home bin shim:"
    ls -l "$HOME/bin/gradle" 2>/dev/null || true
    echo "=============================="
    echo
  } >>"$LOG" 2>&1
}


# ---------- Self-relocate to safe path (WSL/permissions safe) ----------
SAFE_DIR="$HOME/.autoconfig"
SELF="$(readlink -f "$0" 2>/dev/null || printf "%s" "$0")"
case "$PWD" in
  /mnt/*|/media/*|/Volumes/*)
    if [ -z "$AUTOCONFIG_RELOCATED" ]; then
      mkdir -p "$SAFE_DIR" 2>/dev/null
      cp -f "$SELF" "$SAFE_DIR/auto.sh" 2>/dev/null || true
      chmod +x "$SAFE_DIR/auto.sh" 2>/dev/null || true
      echo "Relocating execution to $SAFE_DIR/auto.sh (safer filesystem)..." | tee -a "$LOG"
      AUTOCONFIG_RELOCATED=1 exec env AUTOCONFIG_RELOCATED=1 bash "$SAFE_DIR/auto.sh" "$@"
      exit 0
    fi
    ;;
esac

touch "$LOG"
echo "== Universal Java Dev Installer (quiet, fail-safe) ==" | tee -a "$LOG"
echo "Log: $LOG"
is_wsl && echo "(Detected WSL)" | tee -a "$LOG"

# ---------- SUDO preflight (single prompt, then non-interactive) ----------
SUDO=""; KEEPALIVE_PID=""
if [ "$EUID" -ne 0 ]; then
  if have sudo; then
    if ! sudo -n true 2>/dev/null; then
      echo "Elevating privileges with sudo…" | tee -a "$LOG"
      sudo -v || { echo "ERROR: sudo authentication failed." | tee -a "$LOG"; exit 1; }
    fi
    # keep sudo fresh quietly
    ( while sleep 60; do sudo -n true >>"$LOG" 2>&1 || exit; done ) &
    KEEPALIVE_PID=$!; trap 'kill '"$KEEPALIVE_PID"' 2>/dev/null' EXIT
    SUDO="sudo -n"
  else
    echo "WARNING: sudo not found and not root. Package installs may fail." | tee -a "$LOG"
  fi
fi

# ---------- Detect OS / PM ----------
if [ -f /etc/os-release ]; then . /etc/os-release; fi
DIST_ID="${ID:-unknown}"; DIST_VER="${VERSION_ID:-unknown}"

PM="unknown"; PM_UPDATE=""; PM_INSTALL=""
if have apt-get; then
  PM="apt"
  PM_UPDATE="$SUDO apt-get -y -qq update"
  PM_INSTALL="$SUDO env DEBIAN_FRONTEND=noninteractive apt-get -y -qq install"
elif have dnf; then
  PM="dnf"; PM_UPDATE="$SUDO dnf -y -q makecache"; PM_INSTALL="$SUDO dnf -y -q install"
elif have yum; then
  PM="yum"; PM_UPDATE="$SUDO yum -y -q makecache"; PM_INSTALL="$SUDO yum -y -q install"
elif have zypper; then
  PM="zypper"; PM_UPDATE="$SUDO zypper --quiet --non-interactive refresh"; PM_INSTALL="$SUDO zypper --quiet --non-interactive install -y"
elif have apk; then
  PM="apk"; PM_UPDATE="$SUDO apk update >/dev/null"; PM_INSTALL="$SUDO apk add --no-progress --quiet"
elif have pacman; then
  PM="pacman"; PM_UPDATE="$SUDO pacman -Sy --noconfirm --quiet"; PM_INSTALL="$SUDO pacman -S --noconfirm --quiet"
elif have brew; then
  PM="brew"; PM_UPDATE="brew update --quiet"; PM_INSTALL="brew install -q"
elif have pkg; then
  PM="pkg"; PM_UPDATE="$SUDO pkg update -f -q"; PM_INSTALL="$SUDO pkg install -y -q"
elif have port; then
  PM="port"; PM_UPDATE="$SUDO port -q selfupdate"; PM_INSTALL="$SUDO port -N install"
fi

echo "Detected: ID=$DIST_ID VER=$DIST_VER PM=$PM" | tee -a "$LOG"

# ---------- Retry & apt recovery helpers ----------
retry() {  # retry "<cmd>" [max] [delay]
  local n=0 max=${2:-3} delay=${3:-5}
  until [ $n -ge $max ]; do
    bash -lc "$1" >>"$LOG" 2>&1 && return 0
    n=$((n+1)); sleep "$delay"
  done
  return 1
}
apt_recover() {
  # common apt/dpkg recovery without prompts
  $SUDO dpkg --configure -a >>"$LOG" 2>&1 || true
  $SUDO apt-get -y -qq -f install >>"$LOG" 2>&1 || true
}

pm_try_install(){
  local pkgs=(); for p in "$@"; do [ -n "$p" ] && pkgs+=("$p"); done
  [ ${#pkgs[@]} -eq 0 ] && return 0
  case "$PM" in
    apt)
      say "APT update/refresh"
      if retry "$PM_UPDATE" 5 6; then ok; else
        no "APT update/refresh"; apt_recover; if retry "$PM_UPDATE" 3 6; then ok; else return 1; fi
      fi
      say "Install: ${pkgs[*]}"
      if retry "$PM_INSTALL ${pkgs[*]}" 5 6; then ok; else
        no "Install: ${pkgs[*]}"; apt_recover; if retry "$PM_INSTALL ${pkgs[*]}" 3 6; then ok; else return 1; fi
      fi
      ;;
    dnf|yum|zypper|apk|pacman)
      say "${PM^^} update/refresh"
      if retry "$PM_UPDATE" 3 6; then ok; else no "${PM^^} update/refresh"; return 1; fi
      say "Install: ${pkgs[*]}"
      if retry "$PM_INSTALL ${pkgs[*]}" 3 6; then ok; else no "Install: ${pkgs[*]}"; return 1; fi
      ;;
    brew)
      say "brew update"
      if retry "$PM_UPDATE" 2 0; then ok; else no "brew update"; return 1; fi
      say "Install: ${pkgs[*]}"
      if retry "$PM_INSTALL ${pkgs[*]}" 2 0; then ok; else no "Install: ${pkgs[*]}"; return 1; fi
      ;;
    pkg)
      say "PKG update"
      if retry "$PM_UPDATE" 2 6; then ok; else no "PKG update"; return 1; fi
      say "Install: ${pkgs[*]}"
      if retry "$PM_INSTALL ${pkgs[*]}" 3 6; then ok; else no "Install: ${pkgs[*]}"; return 1; fi
      ;;
    port)
      say "MacPorts selfupdate"
      if retry "$PM_UPDATE" 1 0; then ok; else no "MacPorts selfupdate"; return 1; fi
      say "Install: ${pkgs[*]}"
      if retry "$PM_INSTALL ${pkgs[*]}" 1 0; then ok; else no "Install: ${pkgs[*]}"; return 1; fi
      ;;
    *)
      no "Package install (${PM})"; return 1
      ;;
  esac
}

# Ensure C/C++ compiler exists for Gradle native builds
ensure_cpp_toolchain(){
  # Already present?
  if command -v g++ >/dev/null 2>&1 || command -v clang++ >/dev/null 2>&1; then
    return 0
  fi
  section "C/C++ toolchain"
  case "$PM" in
    apt)      pm_try_install build-essential ;;
    dnf|yum)  pm_try_install gcc gcc-c++ make ;;
    zypper)   pm_try_install gcc gcc-c++ make ;;
    apk)      pm_try_install build-base ;;
    pacman)   pm_try_install base-devel ;;
    brew)
      pm_try_install llvm make
      # Make brewed clang visible to child shells used by run()
      export PATH="/opt/homebrew/opt/llvm/bin:/usr/local/opt/llvm/bin:$PATH"
      ;;
    pkg)      pm_try_install llvm gmake ;;
    port)
      pm_try_install clang-17
      export PATH="/opt/local/libexec/llvm-17/bin:$PATH"
      ;;
    *)
      echo "WARNING: Unknown package manager '$PM'; cannot auto-install C++ toolchain." | tee -a "$LOG"
      ;;
  esac
}

# Ensure Python 3 + pip + venv (best effort across PMs)
ensure_python(){
  section "Python 3 toolchain"
  case "$PM" in
    apt)      pm_try_install python3 python3-venv python3-pip ;;
    dnf|yum)  pm_try_install python3 python3-pip ;;                # venv is in stdlib
    zypper)   pm_try_install python3 python3-pip python3-virtualenv ;;
    apk)      pm_try_install python3 py3-pip ;;                    # venv provided by python3
    pacman)   pm_try_install python python-pip ;;
    brew)     pm_try_install python ;;                             # venv included
    pkg)      pm_try_install python3 ;;                            # pip via ensurepip later
    port)     pm_try_install python312 || pm_try_install python311 || pm_try_install python310 ;;
    *)        echo "WARNING: Unknown PM '$PM'; skipping Python install step." | tee -a "$LOG" ;;
  esac
}

python_tests(){
  section "Python 3 tooling + tests"
  ensure_python

  DEVROOT="${DEVROOT:-$HOME/dev}"
  PYROOT="$DEVROOT/python-sample"

  # fresh workspace + venv
  run "Create virtualenv" "rm -rf '$PYROOT' && mkdir -p '$PYROOT' && python3 -m venv '$PYROOT/.venv'"
  # if some distros ship Python without ensurepip/pip ready, try to bootstrap
  run "Bootstrap pip (ensurepip)" ". '$PYROOT/.venv/bin/activate' && python -m ensurepip --upgrade >/dev/null 2>&1 || true"
  run "Upgrade pip/setuptools/wheel" ". '$PYROOT/.venv/bin/activate' && python -m pip -q install --upgrade pip setuptools wheel"
  run "Install pytest" ". '$PYROOT/.venv/bin/activate' && python -m pip -q install pytest"

  # sample app + tests
  run "Create sample module" "cat >'$PYROOT/app.py' <<'PY'
import math

def add(a, b):
    return a + b

def sqrt(n):
    return math.sqrt(n)
PY"
  run "Create tests" "mkdir -p '$PYROOT/tests' && cat >'$PYROOT/tests/test_app.py' <<'PY'
from app import add, sqrt

def test_add():
    assert add(2, 3) == 5

def test_sqrt():
    assert int(sqrt(16)) == 4
PY"

  # make sure tests can import app.py from project root
  run "Pytest path shim" "cat >'$PYROOT/tests/conftest.py' <<'PY'
import os, sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
PY"

    run "Run pytest" "cd '$PYROOT' && . .venv/bin/activate && PYTHONPATH='$PYROOT' pytest -q"

  # expose for cleanup
  PY_SAMPLE_DIR="$PYROOT"
}




# ---------- Base tooling ----------
section "Base tooling"
pm_try_install ca-certificates curl zip unzip tar gzip

# ---- One-time fast path: only run Python tests (private flag) ----
if [[ "${AUTO_ONLY_PY:-0}" -eq 1 ]]; then
  python_tests
  section "Cleanup"
  CLEAN_ROOTS=()
  [ -n "${PY_SAMPLE_DIR:-}" ] && CLEAN_ROOTS+=("$PY_SAMPLE_DIR")
  run "Remove sanity/smoke test projects" "rm -rf ${CLEAN_ROOTS[@]}"
  echo
  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "SUCCESS — Python toolchain installed & tested. Log: $LOG"
    exit 0
  else
    echo "FAIL — $FAIL_COUNT step(s) failed:"
    for s in "${FAILED_STEPS[@]}"; do echo "   - $s"; done
    echo "See detailed log: $LOG"
    exit 1
  fi
fi


# ---------- JDK + Maven ----------
section "JDK + Maven"
JDK_PKG=""; MAVEN_PKG="maven"
case "$PM:$DIST_ID:$DIST_VER" in
  apt:*)                      JDK_PKG="openjdk-17-jdk" ;;
  dnf:amzn:2023|dnf:amzn:*)   retry "$SUDO dnf -y -q install java-17-amazon-corretto-devel" || JDK_PKG="java-17-openjdk-devel" ;;
  yum:amzn:2)                 ( retry "$SUDO rpm --quiet -Uvh https://rpm.corretto.aws/corretto.repo" && retry "$SUDO yum -y -q install java-17-amazon-corretto-devel" ) || JDK_PKG="java-17-openjdk-devel" ;;
  dnf:*|yum:*)                JDK_PKG="java-17-openjdk-devel" ;;
  zypper:*)                   JDK_PKG="java-17-openjdk-devel" ;;
  apk:*)                      JDK_PKG="openjdk17"; MAVEN_PKG="maven" ;;
  pacman:*)                   JDK_PKG="jdk17-openjdk"; MAVEN_PKG="maven" ;;
  brew:*)                     JDK_PKG="openjdk@17"; MAVEN_PKG="maven" ;;
  pkg:*)                      JDK_PKG="openjdk17";  MAVEN_PKG="maven" ;;   # FreeBSD
  port:*)                     JDK_PKG="openjdk17";  MAVEN_PKG="maven" ;;   # MacPorts
  *:*)                        JDK_PKG="openjdk-17-jdk" ;;
esac
[ -n "$JDK_PKG" ] && pm_try_install "$JDK_PKG"
pm_try_install "$MAVEN_PKG"

# ---------- Gradle via SDKMAN (fallback to package) ----------
section "Gradle via SDKMAN (fallback to package)"
touch "$HOME/.bashrc"
if run "Install SDKMAN!" 'curl -s "https://get.sdkman.io" | bash'; then
  run "Init SDKMAN" 'source "$HOME/.sdkman/bin/sdkman-init.sh"'
  say "Persist SDKMAN init"
  SDKINIT='[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"'
  grep -qxF "$SDKINIT" "$HOME/.bashrc" 2>/dev/null || echo "$SDKINIT" >> "$HOME/.bashrc"
  ok
  run "SDKMAN auto-yes" 'mkdir -p "$HOME/.sdkman/etc"; echo "sdkman_auto_answer=true" > "$HOME/.sdkman/etc/config"'
  if ! run "Install Gradle (SDKMAN)" 'source "$HOME/.sdkman/bin/sdkman-init.sh" && yes | sdk install gradle >/dev/null 2>&1'; then
    pm_try_install gradle
  fi
else
  pm_try_install gradle
fi
# ensure current shell has SDKMAN too
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"

diag


# ---------- JAVA_HOME ----------
section "JAVA_HOME"
say "Configure JAVA_HOME"
JAVA_BIN="$(command -v java || true)"
JAVA_HOME_CALC=""
if [[ "$OSTYPE" == "darwin"* ]] && [ -x /usr/libexec/java_home ]; then
  # Prefer Apple’s resolver on macOS (handles Homebrew openjdk@17 caveats)
  JAVA_HOME_CALC="$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
else
  [ -n "$JAVA_BIN" ] && JAVA_HOME_CALC="$(dirname "$(dirname "$(rlf "$JAVA_BIN")")")"
fi

if [ -n "$JAVA_HOME_CALC" ] && [ -d "$JAVA_HOME_CALC" ]; then
  export JAVA_HOME="$JAVA_HOME_CALC"
  append_once "export JAVA_HOME=\"$JAVA_HOME_CALC\"" "$HOME/.bashrc"
  append_once 'export PATH="$JAVA_HOME/bin:$PATH"' "$HOME/.bashrc"
  ok
else
  no "Configure JAVA_HOME"
fi

# before Versions
diag

# ---------- Versions ----------
section "Versions"
run "java -version" "java -version"

if have mvn; then
  run "mvn -v (quiet)" "mvn -B -q -v --no-transfer-progress"
else
  no "maven present"
fi

if have gradle; then
  run "gradle -v (quiet)" "gradle -q -v --no-daemon"
else
  no "gradle present"
fi


# ---------- Smoke tests ----------
section "Smoke tests"
DEVROOT="$HOME/dev"
MVN_DIR="$DEVROOT/demo-mvn"
GRADLE_DIR="$DEVROOT/demo-gradle"

run "Create Maven project" "mkdir -p '$DEVROOT' && cd '$DEVROOT' && rm -rf '$MVN_DIR' && mvn -B -q --no-transfer-progress archetype:generate -DgroupId=com.example -DartifactId=demo-mvn -DarchetypeArtifactId=maven-archetype-quickstart -DarchetypeVersion=1.4"
run "Run Maven tests"     "cd '$MVN_DIR' && mvn -B -q --no-transfer-progress test"

# Gradle smoke test may include native toolchains in some environments
ensure_cpp_toolchain

if have gradle; then
  run "Create Gradle project" "rm -rf '$GRADLE_DIR' && mkdir -p '$GRADLE_DIR' && gradle -q --no-daemon --console=plain init --project-dir '$GRADLE_DIR' --type java-application --dsl kotlin --test-framework junit-jupiter --project-name demo-gradle --package com.example.app --no-scan --overwrite"
  run "Run Gradle tests" "cd '$GRADLE_DIR' && chmod +x gradlew && ./gradlew -q --no-daemon test"
else
  no "Gradle sample (gradle not installed)"
fi

# ---------- Language prerequisites for Gradle samples ----------
# JVM languages (Java/Kotlin/Groovy/Scala) use Gradle plugins; JDK is already ensured.
# Native samples require a C/C++ compiler; install if missing.
ensure_cpp_toolchain

# ---------- Gradle multi-language tests (top 10) ----------
section "Gradle multi-language tests"
if have gradle; then
  DEVROOT="${DEVROOT:-$HOME/dev}"
  LANG_ROOT="$DEVROOT/gradle-samples"
  run "Prep samples root" "rm -rf '$LANG_ROOT' && mkdir -p '$LANG_ROOT'"

  # Ten popular Gradle-supported project types / languages
  # (java/groovy/kotlin/scala on JVM, plus C++ native)
  GRADLE_SPECS=(
    "java-application:kotlin"
    "java-library:kotlin"
    "kotlin-application:kotlin"
    "kotlin-library:kotlin"
    "groovy-application:groovy"
    "groovy-library:groovy"
    "scala-library:groovy"
    "cpp-application:-"
    "cpp-library:-"
    "java-library:groovy"
  )

  i=0
  for spec in "${GRADLE_SPECS[@]}"; do
    IFS=: read -r TYPE DSL <<<"$spec"
    i=$((i+1))
    DIR="$LANG_ROOT/$i-${TYPE}_${DSL}"
    INIT="gradle -q --no-daemon --console=plain init --project-dir '$DIR' --type $TYPE --no-scan --overwrite"

    # JVM types: add DSL + package + test framework where sensible
    case "$TYPE" in
      java-*|kotlin-*)
        INIT="$INIT --dsl $DSL --package com.example.sample$i --test-framework junit-jupiter"
        ;;
      groovy-*)
        INIT="$INIT --dsl $DSL --package com.example.sample$i --test-framework spock"
        ;;
      scala-*)
        INIT="$INIT --dsl $DSL --package com.example.sample$i"
        ;;
      cpp-*)
        : # no extra flags
        ;;
    esac

    run "Init $TYPE ($DSL DSL)" "rm -rf '$DIR' && mkdir -p '$DIR' && $INIT"
    if [[ "$TYPE" == cpp-* ]]; then
      run "Build $TYPE" "cd '$DIR' && chmod +x gradlew && ./gradlew -q --no-daemon build"
    else
      run "Test $TYPE"  "cd '$DIR' && chmod +x gradlew && ./gradlew -q --no-daemon test"
    fi
  done
else
  no "Gradle multi-language tests (gradle not installed)"
fi

# ---------- Python tests ----------
python_tests


# ---------- Cleanup temp projects ----------
section "Cleanup"
CLEAN_ROOTS=()
CLEAN_ROOTS+=("$MVN_DIR" "$GRADLE_DIR")
CLEAN_ROOTS+=("$HOME/dev/gradle-samples")
[ -n "${PY_SAMPLE_DIR:-}" ] && CLEAN_ROOTS+=("$PY_SAMPLE_DIR")
run "Remove sanity/smoke test projects" "rm -rf ${CLEAN_ROOTS[@]}"


# ---------- WSL notes ----------
if is_wsl; then
  section "WSL notes"
  echo "WSL detected: projects/logs under Linux home (~) for speed & stability. Avoid building under /mnt/c." >> "$LOG"
fi

cd /
wget https://raw.githubusercontent.com/divyamohan1993/devops-shell-scripts/refs/heads/main/maven-gradle-sanity/first-build/app.py
wget https://raw.githubusercontent.com/divyamohan1993/devops-shell-scripts/refs/heads/main/maven-gradle-sanity/first-build/build.gradle
wget https://raw.githubusercontent.com/divyamohan1993/devops-shell-scripts/refs/heads/main/maven-gradle-sanity/first-build/requirements.txt
wget https://raw.githubusercontent.com/divyamohan1993/devops-shell-scripts/refs/heads/main/maven-gradle-sanity/first-build/settings.gradle

gradle runFlask

# ---------- Summary ----------
echo
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "SUCCESS — Java 17, Maven, Gradle installed & verified. Log: $LOG"
  exit 0
else
  echo "FAIL — $FAIL_COUNT step(s) failed:"
  for s in "${FAILED_STEPS[@]}"; do echo "   - $s"; done
  echo "See detailed log: $LOG"
  exit 1
fi


