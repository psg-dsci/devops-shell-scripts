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

<p align="center"><strong>Prepared by:</strong> Divya Mohan (Sole Contributor)</p>
<p align="center"><strong>Trainer:</strong> Prashant Singh Gautam</p>

---

### Academic Information

- **Institution:** Shoolini University  
- **Program:** L&T EduTech — DevOps & Deployment (Hands-on Training)  
- **Repository:** <a href="https://github.com/divyamohan1993/devops-shell-scripts/">github.com/divyamohan1993/devops-shell-scripts</a>

---

## Introduction

<div style="text-align:justify">
This repository is an academic training archive for DevOps and Deployment at Shoolini University in collaboration with L&amp;T EduTech. It consolidates scripts, reproducible labs, and implementation notes that emphasize practical, production-aware skills: shell best practices, containerization, orchestration, CI/CD, Infrastructure as Code, DevSecOps controls, and observability. Content is iterative and versioned as the training progresses, with an emphasis on safe experimentation (VMs/containers), traceable automation, and enterprise-style guardrails.
</div>

---

## Learning Objectives

- Apply **strict, reproducible Bash** patterns with linting, logging, and safe defaults.  
- Build **containerized** workflows and deploy to **Kubernetes** with Helm/Kustomize.  
- Implement **CI/CD** pipelines with quality and security gates (ShellCheck, Semgrep, Trivy, Gitleaks).  
- Manage **Infrastructure as Code** (Terraform/OpenTofu) and environment promotion.  
- Instrument services with **metrics, logging, dashboards**, and actionable alerts.  
- Practice **DevSecOps**: SCA, SAST/DAST, SBOMs & signing, policy-as-code, and runtime monitoring.

---

## Acknowledgment

This training is made possible through academic collaboration between:

<div align="center" style="display:flex;justify-content:center;align-items:center;gap:48px;">
  <a href="https://shooliniuniversity.com/" target="_blank">
    <img src="https://shooliniuniversity.com/assets/images/logo.png" alt="Shoolini University — Logo" width="160">
  </a>
  <a href="https://lntedutech.com/" target="_blank">
    <img src="https://lntedutech.com/wp-content/uploads/2024/01/edutech_logo.webp" alt="L&T EduTech — Logo" width="180">
  </a>
</div>

<p align="center"><em>Special thanks to the instructor, mentors, and the open-source community for guidance and resources.</em></p>

---

## Table of Contents

1. **Overview & Scope**
   - [Introduction](#introduction)  
   - [Learning Objectives](#learning-objectives)  

2. **Hands-on Materials**
   - [Quick start](#quick-start)  
   - [DevOps — Top 10 Daily Things & Tools](#devops--top-10-daily-things--the-tools-youll-see)  
   - [DevSecOps — Top 10 Daily Things & Tools](#devsecops--top-10-daily-things--the-tools-youll-see)  

3. **Repository Layout**
   - `scripts/` — Bash utilities & installers  
   - `k8s/` — manifests, Helm/Kustomize, kind/minikube helpers  
   - `ci/` — CI snippets (e.g., ShellCheck/Gitleaks/Trivy)  
   - `iac/` — Terraform/OpenTofu samples  
   - `security/` — Semgrep, Trivy/Grype, Syft/CycloneDX, cosign  
   - `observability/` — Prometheus rules, Grafana dashboards, logging agents  

4. **Policy & Credits**
   - [Notes, Credits & Responsible Use](#notes-credits--responsible-use)  
   - License & Trademarks (see **LICENSE**)  

---

> **Scope at a glance:**  
> - Reproducible shell scripts with strict mode, logging, and safety checks  
> - CI-ready snippets (ShellCheck, Gitleaks, Trivy, Semgrep, Syft/CycloneDX)  
> - Kubernetes/Helm basics and local clusters (kind/minikube)  
> - Terraform/OpenTofu starters for common cloud patterns  
> - Prometheus/Grafana quick dashboards and logging agents

---


## Why DevOps

These choices reflect what enterprises actually use day-to-day, backed by 2024–2025 ecosystem reports (Stack Overflow, CNCF, Grafana, GitHub, JetBrains, Sonatype). See references at the end.

---

## DevOps — top 10 daily things & the tools you’ll see

1. **Git-based source control & PR flow**  
   Tools: GitHub / GitLab / Bitbucket. (Git is near-universal across teams.)

2. **CI/CD pipelines**  
   Tools: GitHub Actions, Jenkins, GitLab CI, Azure DevOps, CircleCI.

3. **Containers**  
   Tools: Docker, Podman.

4. **Orchestration / platform**  
   Tools: Kubernetes (+ Helm, Kustomize, Argo CD/Flux). (Cloud-native adoption hit **89%** in 2024; **~80%** run K8s in production.)

5. **Infrastructure as Code**  
   Tools: Terraform/OpenTofu, CloudFormation, Pulumi.

6. **Config & release management**  
   Tools: Ansible, Helm, Packer.

7. **Observability (metrics + dashboards + alerting)**  
   Tools: Prometheus + Grafana; Datadog, New Relic, Splunk.

8. **Centralized logging**  
   Tools: Elastic Stack (Elasticsearch/Logstash/Kibana), Loki, CloudWatch/Stackdriver.

9. **Artifact & container registries**  
   Tools: Artifactory, Nexus, Harbor; GitHub/GitLab Packages; ECR/GCR/ACR. (Open-source consumption at multi-trillion download scale → registries are standard plumbing.)

10. **Project tracking & ChatOps**  
    Tools: Jira / GitHub Issues / Azure Boards; Slack / Microsoft Teams for alerts & runbooks.

---

## DevSecOps — top 10 daily things & the tools you’ll see

1. **Software Composition Analysis (SCA) & dependency updates**  
   Tools: Dependabot, Snyk, OWASP Dependency-Check, Renovate.

2. **Secrets hygiene & leak prevention**  
   Tools: GitHub Secret Scanning, Gitleaks, TruffleHog. (**39M** leaked secrets detected on GitHub in 2024 → secret scanning is table-stakes.)

3. **Static Application Security Testing (SAST) in CI**  
   Tools: SonarQube/SonarCloud, Semgrep, Checkmarx, Veracode, GitLab SAST. (SAST is a core “shift-left” control.)

4. **Dynamic testing of running apps (DAST)**  
   Tools: OWASP ZAP, Burp Suite, StackHawk. (DAST = black-box tests of live apps.)

5. **Container/image & artifact scanning**  
   Tools: Trivy, Grype, Anchore, Clair; Syft for SBOMs.

6. **IaC & K8s policy checks (shift-left)**  
   Tools: Checkov, tfsec/Terrascan; **Policy-as-Code with OPA/Conftest**, Kyverno.

7. **Secrets management**  
   Tools: HashiCorp Vault (incl. HCP Vault), External Secrets Operator, cloud KMS. (Vault is a common enterprise anchor for secrets.)

8. **Supply chain integrity: SBOMs & signing**  
   Tools: Syft/CycloneDX/SPDX for SBOMs; **Sigstore cosign** for signing/attestations.

9. **Runtime & cloud-native threat detection**  
   Tools: **Falco** (CNCF *graduated* project), plus CNAPP/CSPM platforms (Wiz/Prisma/Defender/etc.).

10. **Vulnerability management & SIEM/SOAR**  
    Tools: Tenable Nessus, Qualys, Defender for Cloud; SIEMs: Splunk, Sentinel.

---

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

- **Contributor:** Divya Mohan — learning in public, iterating fast.  
- **Academic context:** Shoolini University × L&T EduTech DevOps training.  
- **Trainer:** Prashant Singh Gautam.

### Responsible use
These scripts are for **learning and prototyping**. Review before running, prefer containers/VMs, and never run unvetted commands on production systems. Replace placeholders, keep secrets out of source control, and enable branch protections + required checks.

### Acknowledgments
Thanks to the instructor, peers, and the broader open-source community whose tools and docs make this work possible.

### Contact & Contributions
Have ideas or spot issues? Please open a **GitHub Issue** in this repo. PRs are welcome as the repo matures.

### License & Trademarks
See **LICENSE** for usage terms. Logos are property of their respective owners and are used here **for identification only**.

<p align="right"><a href="#devops-shell-scripts">Back to top ↑</a></p>
