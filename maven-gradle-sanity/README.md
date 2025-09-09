# Java Dev Autoconfig — **Universal, Fail-Safe**

One-click, **non-interactive** setup for a modern Java development environment across **Ubuntu/Debian (incl. WSL)**, **Amazon Linux 2/2023**, **RHEL/CentOS/Fedora**, **openSUSE**, **Alpine**, and **Arch**.

The installer:

* Detects your distro/WSL automatically
* Installs **JDK 17**, **Maven**, **Gradle** (via **SDKMAN!** with auto-yes; falls back to system package)
* Configures **`JAVA_HOME`** and **`PATH`** (idempotent)
* Runs **quiet smoke tests** for Maven & Gradle
* Prints a clear **SUCCESS/FAIL** summary and writes a timestamped **log**

---

## What gets installed

* **JDK 17** (OpenJDK or Amazon Corretto 17 on Amazon Linux)
* **Maven 3.9.x** (from your distro’s repos)
* **Gradle (latest)** via **SDKMAN!**; if SDKMAN is unavailable, falls back to your distro’s `gradle` package
* Utilities: `curl`, `zip`, `unzip`, `ca-certificates`, plus standard archivers (`tar`, `gzip`) if missing

`JAVA_HOME` is computed from the active `java` binary and appended once to `~/.bashrc`, along with `PATH` updates.

---

## Supported platforms (auto-detected)

* **Ubuntu / Debian** (incl. **WSL** on Windows)
* **Amazon Linux 2 / 2023** (prefers **Corretto 17**)
* **RHEL / CentOS / Fedora** (DNF/YUM)
* **openSUSE** (zypper)
* **Alpine** (apk)
* **Arch** (pacman)

> The script chooses the right package names for each family and uses `-qq/-q` or equivalent to avoid prompts.

---

## Quick start

1. Save the script as **`install_java_env_universal.sh`** (from this repo).
2. Make it executable and run:

```bash
chmod +x install_java_env_universal.sh
bash ./install_java_env_universal.sh
```

That’s it. The run is fully non-interactive.

---

## What the script does (in order)

1. Detects OS/distro + package manager (APT/DNF/YUM/Zypper/APK/Pacman), and **WSL**
2. Installs base tools: `ca-certificates curl zip unzip tar gzip`
3. Installs **JDK 17** (OpenJDK; **Corretto 17** on Amazon Linux if available)
4. Installs **Maven** from your distro
5. Installs **SDKMAN!**, enables auto-yes, installs **Gradle (latest)**

   * If SDKMAN or network fails, **falls back** to distro `gradle`
6. Computes **`JAVA_HOME`**, appends it and `PATH` updates to `~/.bashrc` (idempotent)
7. Logs versions quietly and generates **sample projects** under `~/dev/`:

   * `demo-mvn` via Maven archetype → `mvn test`
   * `demo-gradle` via `gradle init` → `./gradlew test`
8. Prints a final **✅ SUCCESS** or **❌ FAIL** with a step list and **log path**

Log file example:

```
~/java_setup_YYYYMMDD_HHMMSS.log
```

---

## Verify after install

Open a **new shell** (or run `source ~/.bashrc`) and check:

```bash
java -version
javac -version
echo "$JAVA_HOME"
mvn -v
gradle -v
```

Optional: run the generated samples again

```bash
cd ~/dev/demo-mvn && mvn -q test
cd ~/dev/demo-gradle && ./gradlew -q test
```

---

## Idempotency & re-runs

* Safe to re-run: the script re-creates sample projects and only appends `JAVA_HOME`/`PATH` once.
* Uses quiet package operations and won’t prompt for input.
* If a step fails (e.g., transient network), re-run the script; it will pick up where needed.

---

## WSL notes

* **WSL** is detected automatically; no extra steps are required.
* For best results, run under **Ubuntu** on WSL and keep Windows antivirus from scanning `~/.m2`/`~/.gradle` aggressively (it can slow builds).

---

## Troubleshooting

* **Package lock / partial upgrades** (Debian/Ubuntu)

  ```bash
  sudo dpkg --configure -a
  sudo apt-get -f install
  ```

  Then re-run the installer.

* **Corporate proxies**

  ```bash
  export http_proxy=http://USER:PASS@HOST:PORT
  export https_proxy=$http_proxy
  ```

  Run the installer in the **same shell**.

* **SDKMAN not installed / Gradle missing**
  The script automatically falls back to your distro’s `gradle`.
  If you prefer SDKMAN later:

  ```bash
  curl -s "https://get.sdkman.io" | bash
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  sdk install gradle
  ```

* **Alpine**
  Alpine’s OpenJDK packages are musl-based; some Java libraries may expect glibc. If a third-party tool complains, consider Ubuntu/Debian for maximum compatibility.

---

## Uninstall / cleanup (optional)

Remove sample projects:

```bash
rm -rf ~/dev/demo-mvn ~/dev/demo-gradle
```

Remove SDKMAN:

```bash
rm -rf "$HOME/.sdkman"
```

Remove toolchains (examples; use your system’s package manager):

* **Debian/Ubuntu**

  ```bash
  sudo apt-get -y purge gradle maven openjdk-17-jdk
  sudo apt-get -y autoremove --purge
  ```

* **RHEL/CentOS/Fedora (DNF)**

  ```bash
  sudo dnf -y remove gradle maven java-17-openjdk-devel
  ```

* **Amazon Linux 2/2023**

  ```bash
  sudo dnf -y remove gradle maven java-17-amazon-corretto-devel || true
  sudo dnf -y remove java-17-openjdk-devel || true
  ```

* **openSUSE**

  ```bash
  sudo zypper --non-interactive remove gradle maven java-17-openjdk-devel
  ```

* **Alpine**

  ```bash
  sudo apk del gradle maven openjdk17
  ```

* **Arch**

  ```bash
  sudo pacman -Rns --noconfirm gradle maven jdk17-openjdk
  ```

Remove the `JAVA_HOME`/`PATH` lines from `~/.bashrc` if you no longer want them.

---

## Security & maintenance

* Packages originate from your **system repos**; Gradle via **SDKMAN!** (official).
* Keep your system updated (`apt-get upgrade`, `dnf upgrade`, etc.).
* For multiple JDKs, install via SDKMAN and switch with:

  ```bash
  sdk list java
  sdk install java 21.0.**-tem
  sdk default java 21.0.**-tem
  ```

---

## License

MIT — do what you want, just don’t sue.
