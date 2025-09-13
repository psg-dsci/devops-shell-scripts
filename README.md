<a name="top"></a>

<div align="center" style="display:flex;justify-content:center;align-items:center;gap:48px;">
  <a href="https://shooliniuniversity.com/" target="_blank">
    <img src="https://shooliniuniversity.com/assets/images/logo.png" alt="Shoolini University — Logo" height="72">
  </a>
  <a href="https://lntedutech.com/" target="_blank">
    <img src="https://lntedutech.com/wp-content/uploads/2024/01/edutech_logo.webp" alt="L&T EduTech — Logo" height="72">
  </a>
</div>

<h1 align="center">DevOps & Deployment — L&amp;T EduTech Training Repository</h1>

<p align="center">Prepared by <strong>Divya Mohan</strong> under the guidance of <strong>Prashant Singh Gautam</strong></p>

### Academic Information

- **Institution:** Shoolini University  
- **Program:** L&T EduTech — DevOps & Deployment (Hands-on Training)  
- **Repository:** <a href="https://github.com/divyamohan1993/devops-shell-scripts/">github.com/divyamohan1993/devops-shell-scripts</a>

---

## Introduction

<div style="text-align: justify !important">
This repository is an academic training archive for DevOps and Deployment at Shoolini University in collaboration with L&amp;T EduTech. It consolidates scripts, reproducible labs, and implementation notes that emphasize practical, production-aware skills: shell best practices, containerization, orchestration, CI/CD, Infrastructure as Code, DevSecOps controls, and observability. Content is iterative and versioned as the training progresses, with an emphasis on safe experimentation (VMs/containers), traceable automation, and enterprise-style guardrails.
</div>

## Learning Objectives

- Apply **strict, reproducible Bash** patterns with linting, logging, and safe defaults.  
- Build **containerized** workflows and deploy to **Kubernetes** with Helm/Kustomize.  
- Implement **CI/CD** pipelines with quality and security gates (ShellCheck, Semgrep, Trivy, Gitleaks).  
- Manage **Infrastructure as Code** (Terraform/OpenTofu) and environment promotion.  
- Instrument services with **metrics, logging, dashboards**, and actionable alerts.  
- Practice **DevSecOps**: SCA, SAST/DAST, SBOMs & signing, policy-as-code, and runtime monitoring.

## Methodology & Lab Format

<div style="text-align: justify !important">
Each section follows a simple loop so you can learn fast and safely:
</div>

1. **Set up** a minimal, isolated environment (container or throwaway VM).  
2. **Execute** the script or workflow (with strict Bash flags and logging).  
3. **Validate** via checks (lint, tests, scans, or health probes).  
4. **Observe** with basic telemetry (logs/metrics) and note outcomes.  
5. **Reflect**: record what changed, what broke, and how to harden next time.

> **Guardrails:** default to least privilege, avoid hard-coded secrets, prefer env vars and .env files (never commit real secrets), and keep scripts idempotent.

---

## Environment & Prerequisites

- Linux/macOS shell (Bash ≥ 4), `curl`, `jq`, `git`  
- **Containers:** Docker or Podman; optional: kind/minikube, `kubectl`, **Helm**  
- **IaC:** Terraform or **OpenTofu**  
- **Security tooling (optional to start):** ShellCheck, Gitleaks, Trivy, Semgrep, Syft/CycloneDX, cosign

## Repository Structure

```

scripts/          # Bash utilities, installers, helpers
k8s/              # Manifests, Helm/Kustomize, kind/minikube assets
ci/               # Reusable CI snippets (ShellCheck/Gitleaks/Trivy/etc.)
iac/              # Terraform/OpenTofu samples
security/         # Semgrep, Trivy/Grype, Syft/CycloneDX, cosign
observability/    # Prometheus rules, Grafana dashboards, logging agents

````

## How to Use This Repository

1) **Clone & explore**
```bash
git clone https://github.com/divyamohan1993/devops-shell-scripts.git
cd devops-shell-scripts
````

2. **Run a script safely**

```bash
# strict mode + trace; run inside a container/VM when possible
bash -euxo pipefail scripts/your-script.sh
```

3. **Validate & learn**

```bash
# lint
shellcheck ./scripts/**/*.sh || true

# quick scans (optional)
trivy image alpine:3.20
gitleaks detect --no-banner
```

---

## Table of Contents

1. **Overview & Scope**

   * [Introduction](#introduction)
   * [Learning Objectives](#learning-objectives)
   * [Methodology & Lab Format](#methodology--lab-format)
   * [Environment & Prerequisites](#environment--prerequisites)
   * [Repository Structure](#repository-structure)
   * [How to Use This Repository](#how-to-use-this-repository)

2. **Hands-on Materials**

   * [Quick start](#quick-start)
   * [DevOps — Top 10 Daily Things & the Tools You’ll See](#devops--top-10-daily-things--the-tools-youll-see)
   * [DevSecOps — Top 10 Daily Things & the Tools You’ll See](#devsecops--top-10-daily-things--the-tools-youll-see)

3. **Policy & Credits**

   * [Notes, Credits & Responsible Use](#notes-credits--responsible-use)
   * License & Trademarks (see **LICENSE**)

---

## Why DevOps

<div style="text-align: justify !important">
Before diving into specific tools, this course emphasizes the outcomes DevOps enables: repeatable builds, safe releases, faster feedback, and secure-by-default systems. The following “Top 10” lists map these outcomes to the most common, enterprise-grade capabilities you’ll exercise in labs and in real-world teams.
</div>

## DevOps — Top 10 Daily Things & the Tools You’ll See

1. **Git-based source control & PR flow**
   Tools: GitHub / GitLab / Bitbucket. (Git is near-universal across teams.)

2. **CI/CD pipelines**
   Tools: GitHub Actions, Jenkins, GitLab CI, Azure DevOps, CircleCI.

3. **Containers**
   Tools: Docker, Podman.

4. **Orchestration / platform**
   Tools: Kubernetes (+ Helm, Kustomize, Argo CD/Flux). (Cloud-native adoption is widespread; K8s is common in production.)

5. **Infrastructure as Code**
   Tools: Terraform/OpenTofu, CloudFormation, Pulumi.

6. **Config & release management**
   Tools: Ansible, Helm, Packer.

7. **Observability (metrics + dashboards + alerting)**
   Tools: Prometheus + Grafana; Datadog, New Relic, Splunk.

8. **Centralized logging**
   Tools: Elastic Stack (Elasticsearch/Logstash/Kibana), Loki, **AWS CloudWatch / Google Cloud Logging (formerly Stackdriver)**.

9. **Artifact & container registries**
   Tools: Artifactory, Nexus, Harbor; GitHub/GitLab Packages; ECR/GCR/ACR.

10. **Project tracking & ChatOps**
    Tools: Jira / GitHub Issues / Azure Boards; Slack / Microsoft Teams for alerts & runbooks.

## DevSecOps — Top 10 Daily Things & the Tools You’ll See

1. **Software Composition Analysis (SCA) & dependency updates**
   Tools: Dependabot, Snyk, OWASP Dependency-Check, Renovate.

2. **Secrets hygiene & leak prevention**
   Tools: GitHub Secret Scanning, Gitleaks, TruffleHog.

3. **Static Application Security Testing (SAST) in CI**
   Tools: SonarQube/SonarCloud, Semgrep, Checkmarx, Veracode, GitLab SAST.

4. **Dynamic testing of running apps (DAST)**
   Tools: OWASP ZAP, Burp Suite, StackHawk.

5. **Container/image & artifact scanning**
   Tools: Trivy, Grype, Anchore, Clair; Syft for SBOMs.

6. **IaC & K8s policy checks (shift-left)**
   Tools: Checkov, tfsec/Terrascan; **Policy-as-Code with OPA/Conftest**, Kyverno.

7. **Secrets management**
   Tools: HashiCorp Vault (incl. HCP Vault), External Secrets Operator, cloud KMS.

8. **Supply chain integrity: SBOMs & signing**
   Tools: Syft/CycloneDX/SPDX for SBOMs; **Sigstore cosign** for signing/attestations.

9. **Runtime & cloud-native threat detection**
   Tools: **Falco**; plus CNAPP/CSPM platforms (Wiz/Prisma/Defender/etc.).

10. **Vulnerability management & SIEM/SOAR**
    Tools: Tenable Nessus, Qualys, Defender for Cloud; SIEMs: Splunk, Sentinel.

## Quick start

```bash
# lint shell scripts (add to CI)
shellcheck ./scripts/**/*.sh

# run safely: strict mode + trace
bash -euxo pipefail scripts/your-script.sh

# container scan examples
trivy image alpine:3.20
grype alpine:3.20

# IaC checks
checkov -d ./iac
```

---

## Notes, Credits & Responsible Use

* **Contributor:** Divya Mohan — learning in public, iterating fast.
* **Academic context:** Shoolini University × L\&T EduTech DevOps training.
* **Trainer:** Prashant Singh Gautam.

### Responsible use

These scripts are for **learning and prototyping**. Review before running, prefer containers/VMs, and never run unvetted commands on production systems. Replace placeholders, keep secrets out of source control, and enable branch protections + required checks. **No warranty; use at your own risk.**

### Acknowledgments

Thanks to the instructor, peers, and the broader open-source community whose tools and docs make this work possible.

### Contact & Contributions

Have ideas or spot issues? Please open a **GitHub Issue** in this repo. PRs are welcome as the repo matures.

### License & Trademarks

See **LICENSE** for usage terms. Logos are property of their respective owners and are used here **for identification only**.

<p align="right"><a href="#top">Back to top ↑</a></p>
