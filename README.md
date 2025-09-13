<p align="center">
  <a href="https://shooliniuniversity.com/" target="_blank">
    <img src="https://shooliniuniversity.com/assets/images/logo.png" alt="Shoolini University" height="64">
  </a>
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://lntedutech.com/" target="_blank">
    <img src="https://lntedutech.com/wp-content/uploads/2024/01/edutech_logo.webp" alt="L&T EduTech" height="64">
  </a>
</p>

<h1 align="center">DevOps and Deployment - LNT Training</h1>

<p align="center">
  <em>Hands-on DevOps scripts and labs from the Shoolini University × L&amp;T EduTech training program.</em>
</p>

<p align="center">
  <strong>Trainer:</strong> Prashant Singh Gautam &nbsp;•&nbsp; <strong>Prepared by</strong> Divya Mohan
</p>

<p align="center">
  <a href="https://github.com/divyamohan1993/devops-shell-scripts/"><strong>Repository</strong></a>
  &nbsp;•&nbsp; Bash &nbsp;•&nbsp; Docker/K8s &nbsp;•&nbsp; CI/CD &nbsp;•&nbsp; IaC &nbsp;•&nbsp; DevSecOps &nbsp;•&nbsp; Observability
</p>

---

DevOps Shell Scripts - notes, scripts, and real-world experiments from my L&amp;T EduTech DevOps training at Shoolini University. This repo will grow continuously (expect variety: Bash utilities, Docker/Kubernetes workflows, CI/CD snippets, IaC samples, security scans, and observability helpers).

**Repo:** https://github.com/divyamohan1993/devops-shell-scripts/

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
