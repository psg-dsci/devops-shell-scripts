# Java Dev Autoconfig (Ubuntu/WSL)

Non-interactive one-click setup for a modern Java development environment on **Ubuntu** (including **WSL**).
Installs **OpenJDK 17**, **Maven**, **Gradle** (via SDKMAN with auto-yes), configures **JAVA\_HOME**, and runs quiet smoke tests.
Outputs a clear **SUCCESS/FAIL** summary and a **log file** for auditing.

---

## What gets installed

* **OpenJDK 17 (JDK + JRE)**
* **Maven 3.9.x** (from Ubuntu repos)
* **Gradle (latest)** via **SDKMAN!**
  ↳ Auto-fallback to `apt` Gradle if SDKMAN fails
* Base utilities: `curl`, `zip`, `unzip`, `ca-certificates`
* **JAVA\_HOME** is added to `~/.bashrc` and `PATH`

### Smoke tests (silent)

* Creates `~/dev/demo-mvn` using Maven archetype and runs `mvn test`
* Creates `~/dev/demo-gradle` using `gradle init` and runs `./gradlew test`

---

## Requirements

* Ubuntu 22.04+ / 24.04 (native or WSL)
* Internet access
* `sudo` privileges

---

## Quick start

1. Save the script as `install_java_env.sh` (the script you have from this repo).
2. Make it executable and run:

```bash
chmod +x install_java_env.sh
bash ./install_java_env.sh
```

That’s it. The script is fully non-interactive (`-qq/-q` where applicable).

---

## What the script does (step-by-step)

1. `apt-get update` and `apt-get upgrade` in **quiet** mode
2. Installs: `openjdk-17-jdk maven curl zip unzip ca-certificates`
3. Computes `JAVA_HOME` from the `java` path and appends to `~/.bashrc` (idempotent)
4. Installs **SDKMAN!**, enables auto-yes, then installs **Gradle**

   * If SDKMAN install fails, tries `sudo apt-get install gradle`
5. Writes all command output to a timestamped log:
   `~/java_setup_YYYYMMDD_HHMMSS.log`
6. Creates **Maven** and **Gradle** sample projects under `~/dev/` and runs tests
7. Prints a **final summary**:

   * ✅ **SUCCESS** — everything installed and verified
   * ❌ **FAIL** — shows which step(s) failed and where to read the log

---

## Verify after install

Open a **new shell** (or `source ~/.bashrc`), then:

```bash
java -version
javac -version
echo $JAVA_HOME
mvn -v
gradle -v
```

---

## Common issues & fixes

* **Apt lock / partial upgrades**
  Close other package tools, then re-run the script. If needed:

  ```bash
  sudo dpkg --configure -a
  sudo apt-get -f install
  ```

* **Corporate proxy**
  Export your proxy before running:

  ```bash
  export http_proxy=http://USER:PASS@HOST:PORT
  export https_proxy=$http_proxy
  ```

* **JAVA\_HOME not set in current session**
  Either open a new shell or run:

  ```bash
  source ~/.bashrc
  ```

* **SDKMAN failed / no Gradle in PATH**
  The script auto-falls back to `apt` Gradle. If you prefer SDKMAN later:

  ```bash
  curl -s "https://get.sdkman.io" | bash
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  sdk install gradle
  ```

---

## Re-running & idempotency

* Safe to re-run. The script checks/setups `JAVA_HOME` only once, and recreates the two sample projects from scratch (`rm -rf` before generate).
* Logs are kept per run with unique timestamps.

---

## Uninstall / cleanup (optional)

Remove sample projects:

```bash
rm -rf ~/dev/demo-mvn ~/dev/demo-gradle
```

Remove SDKMAN (if you want a clean system):

```bash
rm -rf "$HOME/.sdkman"
```

Remove Gradle (apt variant), Maven, JDK:

```bash
sudo apt-get -y purge gradle maven openjdk-17-jdk
sudo apt-get -y autoremove --purge
```

Remove `JAVA_HOME` lines from `~/.bashrc` if you no longer want them.

---

## Notes

* Gradle via SDKMAN is preferred to keep you on the latest stable release; the script falls back to Ubuntu’s Gradle if SDKMAN isn’t available.
* Change JDK versions later with SDKMAN:

  ```bash
  sdk list java
  sdk install java 21.0.**-tem
  sdk default java 21.0.**-tem
  ```

---

## License

MIT — do what you want, just don’t sue.
