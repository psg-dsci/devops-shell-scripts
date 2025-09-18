# Contents

1. [Foundations (Start Here)](#1-foundations-start-here)
2. [Workload Manifests (YAML that ships)](#2-workload-manifests-yaml-that-ships)
3. [Packaging & Templates (Helm & Kustomize)](#3-packaging--templates-helm--kustomize)
4. [Daily Workflow (kubectl, contexts, namespaces)](#4-daily-workflow-kubectl-contexts-namespaces)
5. [Scheduling & Runtime (reliability knobs)](#5-scheduling--runtime-reliability-knobs)
6. [Data & Storage (PVs, PVCs, CSI)](#6-data--storage-pvs-pvcs-csi)
7. [Networking (Services, Ingress/Gateway, NetworkPolicy)](#7-networking-services-ingressgateway-networkpolicy)
8. [Observability (logs, metrics, traces, events)](#8-observability-logs-metrics-traces-events)
9. [Security Hardening (RBAC, PSA, policy)](#9-security-hardening-rbac-psa-policy)
10. [Supply Chain & Registries (images, signing, pulls)](#10-supply-chain--registries-images-signing-pulls)
11. [Cluster Operations (upgrades, nodes, config)](#11-cluster-operations-upgrades-nodes-config)
12. [GPUs & Specialized Runtimes (device plugins)](#12-gpus--specialized-runtimes-device-plugins)
13. [Cross-Platform & Cloud (EKS/GKE/AKS specifics)](#13-crossplatform--cloud-eksgkeaks-specifics)
14. [CI/CD with Kubernetes (GitOps & rollout)](#14-cicd-with-kubernetes-gitops--rollout)
15. [Troubleshooting Playbook](#15-troubleshooting-playbook)
16. [Patterns, Anti-Patterns & Architecture](#16-patterns-anti-patterns--architecture)
17. [Platform & Control-Plane Security](#17-platform--controlplane-security)
18. [Real-World Ops Runbook](#18-realworld-ops-runbook)

---

## 1) Foundations (Start Here)

**Topics (sub-categories):**

* What Kubernetes is (declarative API, controllers, reconciliation)
* Cluster anatomy: control plane vs nodes; CRI (containerd), CNI, CSI
* Install & verify: kubectl, a local cluster (kind/minikube), kubeconfig & contexts
* Object basics: metadata/spec/status; labels, selectors, annotations

**Learning objectives (80/20)**

* Explain how a Deployment becomes Pods via controllers.
* Switch clusters/namespaces with kubeconfig confidently.
* Read any YAML and tell what it creates and how it’s selected.

**Hands-on (80/20 sprint)**

1. Install kubectl; create a kind cluster; `kubectl get nodes -o wide`.
2. Deploy `nginx` as a Deployment; `kubectl get deploy,rs,pods`.
3. Create a second namespace; switch contexts; list only that ns.

**Proof-of-skill**

* One-page diagram of control plane & node workflow + the exact `kubectl` used.

---

## 2) Workload Manifests (YAML that ships)

**Topics:**

* Pods (init, sidecar, ephemeral containers), Deployments & ReplicaSets
* StatefulSets, DaemonSets, Jobs & CronJobs
* Probes (liveness/readiness/startup), env, volumes, resources
* Strategy: rolling updates, revision history, rollbacks

**Learning objectives (80/20)**

* Write clean manifests for Deployments and Jobs with probes & resources.
* Roll forward/back safely; understand when to use StatefulSet vs Deployment.
* Add a sidecar (e.g., log shipper) without breaking readiness.

**Hands-on**

1. Deployment with `readinessProbe` & resource requests/limits.
2. CronJob that runs a script and writes to a PVC.
3. Add a sidecar container for access logs and prove it’s healthy.

**Proof-of-skill**

* Repo with `/manifests` and a README explaining object choices & probes.

---

## 3) Packaging & Templates (Helm & Kustomize)

**Topics:**

* Helm: charts, values, templating, lint/test; dependency mgmt
* Kustomize: bases/overlays, patches, strategic vs JSON6902
* When to prefer Helm vs Kustomize; mixing sanely
* Jsonnet/YTT (awareness) for platform teams

**Learning objectives**

* Package an app as a Helm chart with sane defaults.
* Build env-specific overlays with Kustomize (dev/stage/prod).
* Avoid values sprawl; document the contract (`values.yaml`).

**Hands-on**

1. Convert raw YAML → Helm chart; publish to an internal chart repo.
2. Create Kustomize overlays for dev/prod toggling replicas, resources, Ingress.
3. `helm test` and `helm upgrade --install` in a test namespace.

**Proof-of-skill**

* `packaging.md` comparing Helm vs Kustomize + a runnable example of both.

---

## 4) Daily Workflow (kubectl, contexts, namespaces)

**Topics:**

* CRUD with `kubectl apply`/`delete`; `--dry-run=server`, `-o yaml`
* Logs, exec, port-forward; `kubectl debug` & ephemeral containers
* Context/namespace helpers; shell autocomplete; `krew` plugins

**Learning objectives**

* Diagnose Pods with logs/exec/describe in minutes.
* Use ephemeral debug containers to triage broken images.
* Maintain a tidy kubeconfig with named contexts.

**Hands-on**

1. Break a Pod (bad env); fix it with `kubectl describe` & logs.
2. Use `kubectl debug` to add tools into a running Pod.
3. Port-forward a DB and run a smoke query.

**Proof-of-skill**

* “Golden kubectl” cheat sheet tailored to your team.

---

## 5) Scheduling & Runtime (reliability knobs)

**Topics:**

* Requests/limits → QoS classes; CPU/mem management
* Probes & graceful termination; `terminationGracePeriodSeconds`
* Taints/tolerations; node/pod affinity & anti-affinity
* Topology spread constraints; PDBs; draining; priority/preemption

**Learning objectives**

* Keep apps highly available across zones using spread + PDB.
* Prevent noisy neighbors with correct requests/limits.
* Drain nodes safely without violating availability SLOs.

**Hands-on**

1. Add topology spread to a Deployment; simulate a zone failure.
2. Create a PDB; roll a node drain and observe behavior.
3. Pin a system DaemonSet via tolerations/affinity.

**Proof-of-skill**

* Runbook showing safe drain/upgrade steps with screenshots/logs.

---

## 6) Data & Storage (PVs, PVCs, CSI)

**Topics:**

* Volumes vs PVC/PV; StorageClasses; dynamic provisioning
* Access modes (RWO/RWX), `ReadWriteOncePod`; reclaim policy
* Volume snapshots & restore; ephemeral volumes; CSI drivers

**Learning objectives**

* Choose the right StorageClass & access mode for each workload.
* Snapshot and restore a stateful app quickly.
* Migrate data safely across StorageClasses.

**Hands-on**

1. Deploy Postgres with a PVC; take a VolumeSnapshot; restore to new PVC.
2. Change reclaim policy and observe behavior on delete.
3. Benchmark RWX vs RWO for a test workload.

**Proof-of-skill**

* Backup/restore SOP with commands and verification steps.

---

## 7) Networking (Services, Ingress/Gateway, NetworkPolicy)

**Topics:**

* Services: ClusterIP/NodePort/LoadBalancer; EndpointSlice; internalTrafficPolicy
* Ingress vs Gateway API; controllers (NGINX, cloud L7)
* DNS in cluster; kube-proxy modes; MTU & hairpin NAT awareness
* NetworkPolicy: default-deny + allow rules; egress control

**Learning objectives**

* Expose services via Ingress/Gateway with TLS and path routing.
* Implement default-deny east/west and permit only required traffic.
* Debug DNS/Service selection issues quickly.

**Hands-on**

1. Deploy a web app with TLS via Gateway or Ingress.
2. Implement `default-deny` NetworkPolicy + explicit allows.
3. Verify EndpointSlices, internal traffic policy, and service reachability.

**Proof-of-skill**

* `networking.md` diagrams of North-South & East-West paths + working manifests.

---

## 8) Observability (logs, metrics, traces, events)

**Topics:**

* Events & structured app logs; cluster logging patterns
* metrics-server, kube-state-metrics; Prometheus fundamentals
* Grafana dashboards (golden signals); Alerting rules
* Tracing with OpenTelemetry Operator

**Learning objectives**

* Surface workload & cluster health with SLO-aligned dashboards.
* Set alerts that catch real issues (not noise).
* Instrument a service with distributed tracing.

**Hands-on**

1. Install metrics-server + kube-prometheus-stack.
2. Create service-level SLO dashboards (RPS/latency/errors/saturation).
3. Add OpenTelemetry sidecar/SDK and view a trace.

**Proof-of-skill**

* Screens of dashboards + alert rules in git.

---

## 9) Security Hardening (RBAC, PSA, policy)

**Topics:**

* RBAC design (least privilege, verbs, aggregation)
* Pod Security Admission (baseline/restricted)
* Policy as code (Kyverno/Gatekeeper): image rules, labels, PSS, defaults
* ImagePullSecrets, private registries, minimal images

**Learning objectives**

* Lock down namespaces with restricted PSA + required labels.
* Enforce policies blocking root, privileged, hostPath, \:latest tags.
* Delegate least-privilege roles to teams safely.

**Hands-on**

1. Apply restricted PSA; verify it blocks bad Pods.
2. Add Kyverno/Gatekeeper policies and test violations.
3. Create a read-only role for a team and bind it.

**Proof-of-skill**

* Security policy bundle in git + proof of denied/allowed workloads.

---

## 10) Supply Chain & Registries (images, signing, pulls)

**Topics:**

* Signed images (cosign/notation); admission checks
* Pull secrets & registry auth; private ECR/GCR/ACR/GHCR
* Image provenance & SBOMs; pinned digests
* Quarantine & promotion repos; retention & GC

**Learning objectives**

* Verify image signatures on admission.
* Pin by digest for prod; keep SBOM artifacts.
* Operate a private registry with retention and GC.

**Hands-on**

1. Sign an image; enforce signature verification via policy.
2. Configure ImagePullSecrets and pull from private registry.
3. Promote images between repos with digest pinning.

**Proof-of-skill**

* `supply-chain.md` with policy screenshots and CI logs.

---

## 11) Cluster Operations (upgrades, nodes, config)

**Topics:**

* Version skew & safe upgrades (control plane first)
* Node lifecycle: cordon/drain/uncordon; autoscaling groups
* Cluster autoscaler (infra), cloud controllers
* Config management: admission configs, API server flags (awareness)

**Learning objectives**

* Plan and execute minor version upgrades without downtime.
* Rotate/replace nodes safely and predictably.
* Keep cluster config in git and auditable.

**Hands-on**

1. Practice a minor upgrade on a test cluster.
2. Rotate a node pool with PDB checks.
3. Validate cluster after upgrade with smoke tests.

**Proof-of-skill**

* Upgrade runbook + success criteria and rollback steps.

---

## 12) GPUs & Specialized Runtimes (device plugins)

**Topics:**

* NVIDIA device plugin & runtimeClass; CDI awareness
* Scheduling GPU workloads; resource quotas for GPUs
* Other device plugins (SR-IOV, AI accelerators)

**Learning objectives**

* Run a GPU workload & verify device visibility.
* Control GPU access via quotas and namespace policy.

**Hands-on**

1. Install NVIDIA plugin; run a CUDA sample Pod; `nvidia-smi`.
2. Add ResourceQuota limiting GPU consumption in a namespace.

**Proof-of-skill**

* GPU quickstart with manifests and benchmark numbers.

---

## 13) Cross-Platform & Cloud (EKS/GKE/AKS specifics)

**Topics:**

* Cloud LB controllers (ALB/NLB, GCLB, App Gateway), annotations
* IAM integration (IRSA/Workload Identity/Managed Identity)
* Regional/zone topologies; multi-cluster ingress/gateway (awareness)
* Costs: node types, spot/preemptible, autoscaling

**Learning objectives**

* Ship a production Ingress with TLS and health checks on your cloud.
* Attach Pods to cloud IAM securely (no node-wide secrets).
* Control cost via node mix & autoscaling.

**Hands-on**

1. Deploy an app with cloud L7/L4 ingress & TLS.
2. Configure workload IAM (e.g., IRSA) and access a secret store.
3. Prove cost deltas between instance types with a load test.

**Proof-of-skill**

* Cloud-specific guide with annotations & IAM config.

---

## 14) CI/CD with Kubernetes (GitOps & rollout)

**Topics:**

* GitOps (Argo CD/Flux): drift detection, app-of-apps, promotion flows
* Progressive delivery (Argo Rollouts): canary/blue-green
* Pre-deploy checks: policy, scans, dry-runs

**Learning objectives**

* Bootstrap GitOps and deploy via pull requests.
* Roll out a canary with automated analysis & rollback.
* Enforce policy/scans in the pipeline before sync.

**Hands-on**

1. Install Argo CD; sync a sample app from git.
2. Add Argo Rollouts with a 10%→50%→100% canary.
3. Break policy in a PR and show it getting blocked.

**Proof-of-skill**

* CI/CD YAML + Argo screenshots + a rollback event.

---

## 15) Troubleshooting Playbook

**Topics:**

* CrashLoopBackOff & OOMKill triage; probe failures
* “Pending” Pods (quota, PDB, affinity, taints)
* Service/Ingress 502/503; DNS issues; EndpointSlice gaps
* PVC/PV binding & node mount errors; Events great-circle

**Learning objectives**

* Identify failures fast from `describe`, Events, and logs.
* Map symptoms → subsystem (sched/net/storage/security).

**Hands-on**

1. Reproduce: bad readiness probe; fix and confirm.
2. Reproduce: Pending Pod due to quota/taint; resolve.
3. Reproduce: PVC stuck; fix StorageClass/binding.

**Proof-of-skill**

* `troubleshooting.md`: symptom → commands → root cause → fix.

---

## 16) Patterns, Anti-Patterns & Architecture

**Topics:**

* 12-factor defaults for k8s; config via env/Secrets; stdout logs
* Multi-tenancy: namespaces, quotas, PSA; team templates
* Don’t: hostPath, privileged, \:latest, in-cluster DBs (for prod)
* Move from single cluster → multi-cluster (when/why)

**Learning objectives**

* Ship “boring good” k8s apps by default.
* Choose tenancy boundaries and templates wisely.

**Hands-on**

1. Create a “Golden Namespace” template with quotas/PSA/labels.
2. Rework a legacy app to 12-factor + readiness + resource caps.

**Proof-of-skill**

* Architecture note with trade-offs and defaults.

---

## 17) Platform & Control-Plane Security

**Topics:**

* API server audit logs; admission webhooks; rate limits
* etcd security (encryption at rest, TLS, snapshots)
* Securing the kubelet & node OS; restricted SSH; minimal AMIs
* Secret stores (Vault/Cloud KMS via CSI); rotation runbooks

**Learning objectives**

* Capture/audit sensitive API actions.
* Protect etcd and rotate snapshots/keys.
* Offload secrets to external stores with CSI.

**Hands-on**

1. Enable/collect audit logs and search for a risky action.
2. Take/restore an etcd snapshot in a sandbox.
3. Mount a secret from a provider via CSI & rotate it.

**Proof-of-skill**

* `platform-security.md` + evidence (logs, snapshots, policies).

---

## 18) Real-World Ops Runbook

**Topics:**

* Weekly: image/signature verification, log & event review
* Monthly: base image refresh, Helm/Kustomize dependency bumps
* Quarterly: upgrade rehearsal, backup/DR game day, policy audit
* Pre-release: canary, health checks, capacity & PDB review

**Learning objectives**

* Treat the cluster like a product with time-boxed maintenance.
* Keep evidence (dashboards, logs, tickets) for audits.

**Hands-on**

1. Calendar jobs/pipelines for scans, bumps, and audits.
2. Run a DR drill: restore a namespace from backup.

**Proof-of-skill**

* `ops-runbook.md` with checklists, scripts, and sample reports.
