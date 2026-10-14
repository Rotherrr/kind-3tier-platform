<div align="center">

# ☸️ kind-3tier-platform

**A production-minded, 100% local Kubernetes platform — three-tier app, ingress, persistent storage and full observability, deployed with a single command.**

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Kind](https://img.shields.io/badge/Kind-local%20cluster-0db7ed)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)
![NGINX](https://img.shields.io/badge/NGINX%20Ingress-009639?logo=nginx&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-47A248?logo=mongodb&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)
![Cloud cost](https://img.shields.io/badge/cloud%20cost-%240-success)

</div>

---

## 📌 Overview

This repository is the automated, local-first evolution of a manual Kubernetes workshop (originally built around AWS services). Every cloud-specific dependency was replaced with an open-source equivalent, and every manual step was turned into code.

**Why it matters**

| | |
|---|---|
| 🧱 **Reproducible** | `make up` builds the entire stack from zero; `make down` removes it. Idempotent, so re-running is safe. |
| 🔐 **Secure by default** | Pod Security `restricted`, non-root containers, read-only root FS, dropped capabilities, NetworkPolicies, no secrets in git. |
| 📈 **Observable** | kube-prometheus-stack, a custom `/metrics` endpoint scraped via `ServiceMonitor`, Grafana dashboard 1860 provisioned as code. |
| 💸 **Zero cost** | Runs on a laptop. No cloud account, registry or load balancer required. |
| ✅ **Verified** | A smoke test exercises the real request path (Ingress → Frontend → API → MongoDB), and CI runs lint + the full end-to-end flow. |

---

## 🏗️ Architecture

```
                         ┌───────────────────────── Kind cluster (Docker) ─────────────────────────┐
                         │                                                                          │
   Browser / curl        │   ns: ingress-nginx            ns: three-tier                            │
 http://localhost  ──────┼─► ┌──────────────┐  /      ┌────────────────┐                            │
   :80 / :443            │   │    NGINX     │────────►│  Frontend (x2) │                            │
 (host port mapping)     │   │   Ingress    │         │ nginx-unpriv.  │                            │
                         │   │  Controller  │  /api   ├────────────────┤     ┌───────────────────┐  │
                         │   │              │────────►│  Backend  (x2) │────►│ MongoDB           │  │
                         │   └──────┬───────┘         │ Node.js + prom │     │ StatefulSet + PVC │  │
                         │          │                 └───────▲────────┘     └───────────────────┘  │
 grafana.localtest.me ───┼──────────┘                         │ scrape /metrics (ServiceMonitor)    │
                         │                    ns: monitoring  │                                      │
                         │              ┌─────────────┐   ┌───┴────────┐   ┌───────────────────┐    │
                         │              │   Grafana   │──►│ Prometheus │◄──│ node-exporter /   │    │
                         │              │ (dash. 1860)│   │            │   │ kube-state-metrics│    │
                         │              └─────────────┘   └────────────┘   └───────────────────┘    │
                         └──────────────────────────────────────────────────────────────────────────┘
```

Request flow: **Client → NGINX Ingress → Frontend / Backend → MongoDB.** A Mermaid version lives in [`docs/architecture.md`](docs/architecture.md).

---

## 🧰 Tech Stack — Local vs. Cloud Equivalent

| Concern | This project (local) | Typical cloud equivalent |
|---|---|---|
| Kubernetes cluster | **Kind** (multi-node, in Docker) | Amazon EKS |
| Ingress / L7 load balancing | **NGINX Ingress Controller** | AWS Load Balancer Controller (ALB) |
| Image registry | **Local build + `kind load docker-image`** | Amazon ECR |
| Persistent storage | **PVC via Kind's local-path provisioner** | EBS CSI driver |
| Database | **MongoDB StatefulSet** | DocumentDB / Atlas |
| Monitoring | **kube-prometheus-stack (Helm)** | Managed Prometheus + Managed Grafana |
| Secrets | **Kubernetes Secret (generated at deploy time)** | AWS Secrets Manager + External Secrets |
| DNS | **`*.localtest.me` → 127.0.0.1** | Route 53 |

---

## ✅ Prerequisites

| Tool | Purpose |
|---|---|
| `docker` | Container runtime for Kind and image builds |
| `kind` | Local Kubernetes cluster |
| `kubectl` | Cluster CLI (≥ 1.27, for `kubectl apply -k`) |
| `helm` | Installs kube-prometheus-stack |
| `make`, `curl`, `openssl` | Automation, smoke tests, random password |

Ports **80** and **443** must be free on the host. Allow ~6 GB RAM for Docker.

---

## 🚀 Quick Start

```bash
git clone https://github.com/<your-user>/kind-3tier-platform.git
cd kind-3tier-platform
make up
```

`make up` runs, in order:

1. `preflight` – verifies tools and the Docker daemon
2. `cluster` – creates a Kind cluster (1 control-plane + 2 workers, ports 80/443 mapped)
3. `ingress` – installs the NGINX Ingress Controller (pinned version)
4. `images` – builds frontend/backend and side-loads them with `kind load docker-image`
5. `monitoring` – Helm-installs kube-prometheus-stack with Grafana dashboard 1860
6. `deploy` – generates the MongoDB Secret and applies all manifests via Kustomize
7. `smoke` – end-to-end test through the ingress

> ⏱️ First run takes a few minutes (it pulls images); subsequent runs are much faster. Everything is idempotent.

| Endpoint | URL |
|---|---|
| Application | http://localhost |
| Grafana | http://grafana.localtest.me |

```bash
make help     # list all targets
make status   # pods / services / ingress / PVCs
make down     # delete the cluster
```

---

## 📊 Monitoring & Observability

1. Open **http://grafana.localtest.me**
2. Log in with **`admin` / `prom-operator`** (local-only demo credential)
3. **Dashboard 1860 ("Node Exporter Full") is already provisioned** under *Dashboards → Community*, via Helm values (dashboards-as-code). To import it manually instead: *Dashboards → New → Import → ID `1860` → Load → select the `Prometheus` data source*.
4. The backend exposes `/metrics` (default Node.js metrics + `http_request_duration_seconds`), scraped through a `ServiceMonitor`. Try in Explore:

```promql
sum(rate(http_request_duration_seconds_count{namespace="three-tier"}[1m])) by (route, status)
```

---

## 🧠 Engineering Decisions & Trade-offs

> Written for interviewers: what I chose, why, and what I would change in production.

| Decision | Rationale | Trade-off / production note |
|---|---|---|
| **Kind over Minikube** | Multi-node clusters in seconds, runs identically in CI, no VM layer. | No built-in LoadBalancer; solved with a host port mapping on the ingress-ready node. |
| **Side-loading images (`kind load`)** | Removes the registry from the loop; `imagePullPolicy: IfNotPresent` and a non-`latest` tag. | In production: CI pushes immutable, signed tags (digest-pinned) to a registry. |
| **MongoDB as a StatefulSet + PVC** | Stable identity, and data survives pod restarts and rescheduling. | Single replica = no HA. Production: replica set via an operator, or a managed DB. |
| **Secret generated at deploy time** | No credentials in git; random per environment; kept idempotently so the existing PVC keeps working. | Native Secrets are only base64. Production: External Secrets / Sealed Secrets / Vault + encryption at rest. |
| **Pod Security `restricted` + hardened contexts** | Non-root, `readOnlyRootFilesystem`, `drop: ALL`, `RuntimeDefault` seccomp, no SA token mounted. | Required `nginx-unprivileged` and an `emptyDir` for `/tmp`; a small price for a much smaller attack surface. |
| **NetworkPolicies (default-deny ingress)** | Only Ingress → app, Backend → MongoDB, Prometheus → Backend are allowed. | Enforcement depends on the CNI; verify it on your Kind version, or run Kind with Calico/Cilium for guaranteed enforcement. Egress policies are a next step. |
| **Separate liveness / readiness / startup probes** | Readiness depends on MongoDB (traffic stops if the DB is down) while liveness does not (avoids restart storms). | — |
| **Resource requests & limits everywhere** | Predictable scheduling, protects a laptop; memory limits sized for a dev workload. | Limits would be tuned from real load tests; add HPA + metrics-server. |
| **PodDisruptionBudgets + rolling updates (`maxUnavailable: 0`)** | Zero-downtime deploys and node drains. | — |
| **Kustomize for app, Helm for third-party** | Plain, reviewable YAML for our code; the community chart for the complex monitoring stack. | Could be unified under Helm/Argo CD for GitOps. |
| **Pinned versions** | Reproducible builds (ingress controller tag, image tags; Grafana dashboard revision). | Needs periodic upgrades (Renovate/Dependabot). |
| **Ingress controller choice** | NGINX Ingress is the de-facto standard and works in Kind. | The Kubernetes project has announced the retirement of ingress-nginx (2026), so for new production work I would evaluate Gateway API implementations. |

**Local vs. cloud, honestly:** this setup deliberately does not simulate cloud-only behavior (multi-AZ, IAM roles, managed LB, autoscaling nodes). It demonstrates the Kubernetes fundamentals that stay the same everywhere.

---

## 🛠️ Troubleshooting & Useful Commands

```bash
# Overview
kubectl -n three-tier get pods,svc,ingress,pvc -o wide
kubectl get pods -A

# Logs
kubectl -n three-tier logs -l app.kubernetes.io/name=backend --tail=100 -f
kubectl -n three-tier logs statefulset/mongodb
kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=100

# Why is a pod not ready?
kubectl -n three-tier describe pod <pod>
kubectl -n three-tier get events --sort-by=.lastTimestamp

# Ingress
kubectl -n three-tier describe ingress three-tier
curl -i http://localhost/api/messages

# Reach MongoDB / services without the ingress
kubectl -n three-tier port-forward svc/backend 3000:3000

# Rebuild after a code change
make images && kubectl -n three-tier rollout restart deploy/backend deploy/frontend
```

| Symptom | Likely cause / fix |
|---|---|
| `bind: address already in use` on cluster creation | Something uses port 80/443. Stop it, or change `hostPort` in `kind-config.yaml`. |
| `ImagePullBackOff` on frontend/backend | Image was not loaded: run `make images`. |
| Backend `0/1 Ready` | MongoDB not ready yet; check `kubectl -n three-tier logs sts/mongodb`. |
| `grafana.localtest.me` doesn't resolve | Your DNS blocks rebinding; use `curl -H 'Host: grafana.localtest.me' http://127.0.0.1` or add a hosts entry. |
| Mongo auth fails after recreating the Secret | Credentials are only read on first volume init. `make down` and start fresh (or delete the PVC). |

---

## 🗂️ Repository Structure

```
.
├── Makefile                  # one-command workflow (make help)
├── kind-config.yaml          # cluster definition + 80/443 port mapping
├── app/
│   ├── backend/              # Node.js API (health, readiness, metrics) + multi-stage Dockerfile
│   └── frontend/             # static UI served by nginx-unprivileged
├── k8s/
│   ├── kustomization.yaml
│   ├── 00-namespace.yaml     # PSA "restricted"
│   ├── mongodb/              # StatefulSet + headless Service
│   ├── backend/              # ConfigMap, Deployment, Service
│   ├── frontend/             # Deployment, Service
│   ├── ingress.yaml
│   ├── network-policies.yaml
│   ├── pdb.yaml
│   └── monitoring/           # Helm values (dashboard 1860) + ServiceMonitor
├── scripts/                  # preflight, secrets, smoke-test, teardown
├── docs/architecture.md
└── .github/workflows/ci.yml  # lint + full e2e in CI
```

---

## 🎓 Key Takeaways & What I Learned

- **Automation first:** turning a click-through workshop into an idempotent pipeline exposed hidden ordering dependencies (CRDs before `ServiceMonitor`, ingress readiness before smoke tests).
- **Security is a default, not an add-on:** hardening a workload with `restricted` PSA forced me to understand what each image really needs (writable paths, UIDs, capabilities).
- **Readiness ≠ liveness:** coupling readiness to the database and keeping liveness independent prevents cascading restarts.
- **State is the hard part:** the credentials-vs-PVC interaction taught me why secret rotation and stateful workloads need deliberate design.
- **Observability as code:** provisioning dashboards and scrape targets declaratively makes the environment reproducible and reviewable.
- **Knowing the limits of local:** I can articulate precisely what a laptop cluster does not prove, and what I would add for production (HA data tier, GitOps, External Secrets, image signing, autoscaling).

---

## 🔭 Roadmap

- [ ] Argo CD (GitOps) · [ ] cert-manager + local TLS on :443 · [ ] HPA + metrics-server
- [ ] Alertmanager rules · [ ] Trivy image scanning in CI · [ ] Kyverno policies · [ ] Calico/Cilium for egress policies

## 📄 License

MIT
