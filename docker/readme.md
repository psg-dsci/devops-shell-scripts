# Contents

1. [Foundations (Start Here)](#1-foundations-start-here)
2. [Image Authoring (Dockerfile that ships)](#2-image-authoring-dockerfile-that-ships)
3. [Build System Mastery (BuildKit & Buildx)](#3-build-system-mastery-buildkit--buildx)
4. [Compose for Daily Work](#4-compose-for-daily-work)
5. [Running Containers (runtime knobs)](#5-running-containers-runtime-knobs)
6. [Data & Storage](#6-data--storage)
7. [Networking](#7-networking)
8. [Observability (logs, metrics, events)](#8-observability-logs-metrics-events)
9. [Security Hardening](#9-security-hardening)
10. [Registries & Supply Chain](#10-registries--supply-chain)
11. [Engine & Desktop Operations](#11-engine--desktop-operations)
12. [GPUs & Specialized Runtimes](#12-gpus--specialized-runtimes)
13. [Windows & Cross-Platform](#13-windows--cross-platform-realities)
14. [CI/CD with Docker](#14-cicd-with-docker)
15. [Troubleshooting Playbook](#15-troubleshooting-playbook)
16. [Patterns, Anti-Patterns & Architecture](#16-patterns-anti-patterns--architecture-choices)
17. [Security of the Docker Host](#17-security-of-the-docker-host)
18. [Real-World Ops Runbook](#18-real-world-ops-runbook)

---

## 1) Foundations (Start Here)

**Topics (sub-categories):**

* What containers are (processes, isolation)
* Install & verify (Docker Desktop/Engine, WSL2)
* Core CLI: run/ps/logs/exec/stop/rm/pull/push/inspect
* Image anatomy: layers, digests, tags, OCI

**Learning objectives (80/20)**

* Explain image vs container and lifecycle in one paragraph.
* Run/inspect/exec/log into a container without Googling.
* Pull by tag vs digest and explain when to use each.

**Hands-on (80/20 sprint)**

1. Install Docker; run `hello-world` and `alpine sleep 60`.
2. `docker run -d --name web -p 8080:80 nginx`, then `logs`, `exec -it`, `inspect`.
3. Pull `nginx@<digest>` and compare to `:latest`.

**Proof-of-skill**

* One-page cheat sheet of top 20 CLI commands with sample outputs.
* Screenshot + short note explaining tag vs digest with a working example.

---

## 2) Image Authoring (Dockerfile that ships)

**Topics:**

* Dockerfile instructions, ENTRYPOINT vs CMD, COPY vs ADD
* Multi-stage builds
* .dockerignore hygiene
* Base image comparisons (Alpine/Ubuntu/Distroless/UBI)
* Labels/metadata
* HEALTHCHECK
* Non-root images (`USER`), `--init`

**Learning objectives (80/20)**

* Write a production Dockerfile with multi-stage and non-root user.
* Choose a base image for your app and justify it.
* Add healthcheck and labels for provenance.

**Hands-on**

1. Containerize a tiny API (Node/Python/Go/Java) with multi-stage.
2. Add `.dockerignore`, `HEALTHCHECK`, `USER 10001`.
3. Compare image sizes & start time between Alpine vs Distroless.

**Proof-of-skill**

* Repo with Dockerfile, README explaining design choices, and `docker history` analysis.

---

## 3) Build System Mastery (BuildKit & Buildx)

**Topics:**

* BuildKit basics, cache mounts
* Secrets & SSH at build time
* Multi-arch (buildx + QEMU), manifest lists
* Remote build contexts (git/ssh)
* SBOMs & attestations (awareness)
* Deterministic builds (pinning)

**Learning objectives**

* Use BuildKit features (`--mount=type=cache`, `--secret`).
* Publish a multi-arch image (amd64/arm64) with a manifest list.
* Generate an SBOM from a build pipeline (tool of choice).

**Hands-on**

1. Enable BuildKit; speed up builds with cache mounts.
2. Inject a private key via `--ssh` to pull a private dependency (no layer leaks).
3. Build and push a multi-arch image; verify with `docker buildx imagetools inspect`.

**Proof-of-skill**

* Makefile/Action/CI file that builds multi-arch, uses cache, and emits an SBOM artifact.

---

## 4) Compose for Daily Work

**Topics:**

* Compose Spec (services, networks, volumes)
* Startup ordering via `healthcheck` + `depends_on`
* Environment handling (`.env`, `--env-file`)
* Profiles/overrides for dev/test/prod

**Learning objectives**

* Model a 3-service stack (web, API, DB) with health-gated startup.
* Use profiles to toggle extras (admin UI, worker).
* Keep secrets out of YAML/env files checked into git.

**Hands-on**

1. Compose a web+api+db stack with named volumes and user-defined network.
2. Add healthchecks; gate API on DB readiness.
3. Add `profiles:` to include a “worker” only in prod.

**Proof-of-skill**

* `compose.yaml` + `README` explaining networks, volumes, profiles, and a `make up/down` flow.

---

## 5) Running Containers (runtime knobs)

**Topics:**

* Restart policies (`no`, `on-failure`, `unless-stopped`)
* Resource controls (`--memory`, `--cpus`, `--pids-limit`, ulimits)
* `--init` and PID 1 behavior
* Signals, graceful shutdown

**Learning objectives**

* Apply CPU/memory limits that prevent host starvation.
* Ensure graceful termination with signals and preStop logic.
* Choose the right restart policy for services vs batch jobs.

**Hands-on**

1. Run an API with `--cpus 1 --memory 512m` and prove throttling with `docker stats`.
2. Add `STOPSIGNAL` and test graceful shutdown with `docker stop`.
3. Compare behavior with/without `--init`.

**Proof-of-skill**

* Short “runtime knobs” guide with measured numbers from `docker stats` and logs.

---

## 6) Data & Storage

**Topics:**

* Volumes vs bind mounts (use cases)
* Backups/restores of named volumes
* Storage drivers (overlay2), copy-up behavior
* Build cache hygiene

**Learning objectives**

* Pick volumes by default; use binds for local dev only.
* Back up and restore data volumes reliably.
* Diagnose “no space left on device” from layer buildup.

**Hands-on**

1. Create named volumes for DB; back up via `docker run --rm -v vol:/data ... tar`.
2. Restore into a fresh container and verify integrity.
3. Clean layer/caches safely (`system prune`, build cache prune).

**Proof-of-skill**

* Backup/restore script with dry-run and verification steps.

---

## 7) Networking

**Topics:**

* Bridge vs user-defined bridge (embedded DNS)
* Published ports vs host networking
* macvlan (L2 addressable containers)
* Overlay (concepts), multi-host awareness
* DNS/MTU/hairpin NAT, debugging (`tcpdump`, `dig`)
* Remote engines & `docker context` (SSH)

**Learning objectives**

* Design service discovery using user-defined networks.
* Diagnose port conflicts, DNS failures, MTU issues.
* Operate a remote Docker host via SSH context.

**Hands-on**

1. Two services on a user-defined network; call by service name.
2. Troubleshoot “address already in use” with `ss -ltnp`.
3. Create an SSH context to deploy to a remote VM.

**Proof-of-skill**

* Networking runbook with common fixes and verified commands.

---

## 8) Observability (logs, metrics, events)

**Topics:**

* Logging drivers & rotation (json-file, journald, fluentd/Loki)
* `docker stats` and runtime metrics
* `docker events` stream
* Structured logging & correlation IDs

**Learning objectives**

* Configure log rotation to prevent disk fill.
* Stream resource metrics and set alert thresholds.
* Use `events` to build a simple deploy/audit timeline.

**Hands-on**

1. Configure daemon log rotation; prove by filling logs safely.
2. Ship app logs to a collector (local stack) from containers.
3. Record a deploy timeline with `docker events > timeline.log`.

**Proof-of-skill**

* `observability.md` with config snippets + screenshots of log rotation and metrics.

---

## 9) Security Hardening

**Topics:**

* Least privilege: `USER`, drop capabilities, read-only rootfs, no SSH in images
* Seccomp/AppArmor/SELinux (default profiles, basic tuning)
* Rootless Docker (when/how)
* Secrets patterns (build-time vs runtime)
* Image scanning (Trivy/Grype, Docker Scout)
* CIS Docker Benchmark, Docker Bench for Security

**Learning objectives**

* Ship non-root, minimal images with least capabilities.
* Scan images in CI and fail builds on critical vulns.
* Apply baseline CIS hardening items.

**Hands-on**

1. Harden a Dockerfile: non-root, remove shells, read-only FS + tmpfs mounts.
2. Run Trivy in CI; fail on HIGH/CRITICAL.
3. Run Docker Bench; fix top 5 findings.

**Proof-of-skill**

* Security checklist + CI logs showing a failed scan and a subsequent pass.

---

## 10) Registries & Supply Chain

**Topics:**

* Private registry (auth, storage, GC)
* Mirrors/proxies, custom CAs, air-gapped pulls
* Tags vs digests (prod pinning)
* Signing & provenance (cosign/notation awareness)
* Harbor/ECR/GHCR practices (retention, robot users)

**Learning objectives**

* Deploy a private registry with auth and garbage collection.
* Push/pull via a mirror; trust a custom CA.
* Sign an image and verify signature before deploy.

**Hands-on**

1. Launch a private registry + UI (e.g., Harbor) locally; push/pull images.
2. Configure a registry mirror in `daemon.json`.
3. Sign one image and verify in pipeline.

**Proof-of-skill**

* `supply-chain.md` with registry config, mirror settings, and signature verification logs.

---

## 11) Engine & Desktop Operations

**Topics:**

* `daemon.json` (log driver, live-restore, mirrors, runtimes, proxies)
* Live-restore & daemon reload for upgrades
* Corporate proxies (daemon vs CLI vs container env)
* Desktop + WSL2 performance/layouts

**Learning objectives**

* Tune daemon for your org defaults and proxies.
* Upgrade Docker without killing long-running containers.
* Avoid slow mounts on Windows (correct pathing).

**Hands-on**

1. Set `live-restore`, mirror, log rotation in `daemon.json`; reload daemon.
2. Validate proxy behavior for host vs container.
3. Prove WSL2 mount/layout optimization via timed build.

**Proof-of-skill**

* `engine-ops.md` with the exact `daemon.json` and measured before/after metrics.

---

## 12) GPUs & Specialized Runtimes

**Topics:**

* NVIDIA Container Toolkit; `--gpus`/CDI
* Verify with `nvidia-smi` inside containers
* Awareness: AMD ROCm, TPUs

**Learning objectives**

* Run a CUDA sample container using the host GPU.
* Explain CDI device injection at a high level.

**Hands-on**

1. Install GPU toolkit; run `nvidia/cuda:...` and verify `nvidia-smi`.
2. Limit GPU access to a container; test numeric workload.

**Proof-of-skill**

* Short GPU quickstart with commands + benchmark numbers.

---

## 13) Windows & Cross-Platform Realities

**Topics:**

* Windows containers (process vs Hyper-V isolation)
* Version/OS compatibility matrix basics
* Linux containers on Windows (WSL2 backend)
* Path/FS pitfalls: CRLF, case sensitivity, file sharing

**Learning objectives**

* Choose Windows vs Linux container appropriately.
* Avoid CRLF and permission traps across OSes.

**Hands-on**

1. Build and run a simple Windows container (on a Windows host).
2. Demonstrate CRLF fix and permission fix for a Linux container on Windows.

**Proof-of-skill**

* `cross-platform.md` with gotchas and their fixes (before/after logs).

---

## 14) CI/CD with Docker

**Topics:**

* buildx in CI (Actions/GitLab), remote cache
* Avoid DinD pitfalls; prefer rootless BuildKit or socket proxy
* Scan & gate (SBOM, vuln thresholds, policy checks)
* Sign & push; rollout strategies

**Learning objectives**

* Produce deterministic multi-arch builds in CI with caching.
* Enforce security gates (scan + policy) before push.
* Publish image digests for deployments.

**Hands-on**

1. CI pipeline that builds multi-arch with cache + SBOM artifact.
2. Add Trivy/Grype scanning step with thresholds.
3. Publish digest outputs to an env file for downstream deploy.

**Proof-of-skill**

* CI YAML and a passing run link/logs; artifacts attached.

---

## 15) Troubleshooting Playbook

**Topics:**

* Docker daemon connectivity
* Wrong arch / `exec format error`
* Permissions & bind mounts (SELinux/AppArmor, ownership)
* Networking conflicts, DNS on user-defined networks
* Disk/layers: space pressure, pruning
* Healthchecks & `docker events` timelines

**Learning objectives**

* Diagnose top 10 daily breakages in under 5 minutes.
* Read errors and jump to the right subsystem (net, perms, storage).

**Hands-on**

1. Create controlled failures (port conflict, DNS fail, disk full) and fix them.
2. Use `events` to reconstruct an outage timeline.

**Proof-of-skill**

* `troubleshooting.md` with symptoms → commands → fixes, each reproducible.

---

## 16) Patterns, Anti-Patterns & Architecture Choices

**Topics:**

* 12-factor app practices in containers
* Statefulness: volumes vs managed DBs; backup SLAs
* Compose vs Swarm vs Kubernetes (when to move up)

**Learning objectives**

* Containerize apps following 12-factor defaults out-of-the-box.
* Decide when *not* to run stateful DBs in containers.
* Explain a path from local Compose → Kubernetes.

**Hands-on**

1. Retrofit a sample app to log to stdout, config via env, ephemeral containers.
2. Move a Compose stack to a lightweight k8s (kind/k3d) as awareness.

**Proof-of-skill**

* Architecture note that justifies chosen stack with trade-offs.

---

## 17) Security of the Docker Host

**Topics:**

* Protecting the Docker socket (group access, rootless, authZ plugins)
* Kernel/OS patching, minimal host packages
* CIS hardening routine

**Learning objectives**

* Restrict socket access and rotate credentials/tokens.
* Run periodic host hardening checks and patch cycles.

**Hands-on**

1. Remove broad socket access; use SSH contexts instead.
2. Run Docker Bench weekly; open tickets for findings.

**Proof-of-skill**

* `host-security.md` with hardening steps and sample bench report.

---

## 18) Real-World Ops Runbook

**Topics:**

* Weekly: image scans, log rotation checks, cache pruning
* Monthly: base refresh, SBOM regenerate, rebuilds
* Quarterly: CIS audit, registry GC, mirror latency audit
* Pre-release: pin by digest, verify healthchecks, resource caps

**Learning objectives**

* Operate Docker as a living system with time-boxed maintenance.
* Tie scans/audits to concrete remediation.

**Hands-on**

1. Cron or pipeline jobs for weekly scans & rotations.
2. Quarterly registry GC dry-run + report.

**Proof-of-skill**

* `ops-runbook.md` with calendar, scripts, and evidence logs.

---

## How to break each topic into sub-topics

For each sub-category page, use this micro-structure:

1. **Why it matters in real life** (2–3 bullets tied to reliability/security/cost).
2. **Core concepts** (5 bullets max).
3. **Commands & configs** (copy-paste block).
4. **Hands-on lab** (10–20 min).
5. **Checks & pitfalls** (quick list).
6. **Deliverables** (what to publish to prove skill).

---

## Suggested learning path (zero → expert)

1. Foundations → Image Authoring → Build System → Compose
2. Runtime knobs → Storage → Networking → Observability
3. Security Hardening → Host Security → Supply Chain
4. CI/CD → Windows/GPU (as needed) → Patterns → Ops Runbook
5. Troubleshooting Playbook (kept open daily)

