# Infrastructure & Multi-VM Kubernetes Strategy — Distributed Commerce & Flash Sale Platform

- **Document ID:** `DCP-DOC-INF-001`
- **Status:** `ACCEPTED` (Approved in M0.1 — `Q2` 4–5 VMs & `Q3` Start with `K3s`, Migrate to `kubeadm` Later)
- **Governed By:** [`ADR-0002`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0002-database-per-service-on-shared-postgres-instance.md), [`ADR-0009`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0009-on-prem-kubernetes-k3s-vs-kubeadm-and-storage.md), [`ADR-0010`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0010-event-contracts-json-schema-and-kafka-kraft.md), [`ADR-0011`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0011-observability-opentelemetry-and-lgtm-stack.md)
- **Last Updated:** 2026-11-10

---

## 1. Approved Hardware & Multi-VM Cluster Budget (`Q2 — ACCEPTED`)

Based on the approved hardware envelope (`1` current workspace VM + `3–4` additional Linux VMs of equivalent class), each node has:
- **CPU**: `2 vCPUs` (`ARM64 aarch64` Neoverse-N1 or `x86_64`)
- **Memory**: `3.8 GiB RAM` (`~3,890 MiB`) + configured `2 GiB` swap file ONLY for non-Kubernetes dev nodes (swap disabled on K8s nodes per kubelet requirements, or K8s 1.30+ `NodeSwap` `LimitedSwap` evaluated)
- **Storage**: `29 GiB` root SSD (`~23 GiB` usable free space per VM)

### 1.1 Node Role Allocation across 4–5 VMs (`~15.2–19.0 GiB Total Cluster RAM`)

| Node | Role | Assigned Workloads | Memory Budget Allocation (`3.8 GiB` Total) |
| :--- | :--- | :--- | :--- |
| **VM-1** | **Control Plane, Ingress & GitOps** | `K3s Server` (`--disable traefik --disable servicelb`), `MetalLB`, `Ingress-NGINX`, `Argo CD` | OS/System: `450 MiB` + K3s Server: `550 MiB` + MetalLB/Ingress: `200 MiB` + Argo CD: `650 MiB` = **`~1.85 GiB`** (`~1.95 GiB` headroom for `k6` / CI utilities) |
| **VM-2** | **Stateless Worker Node A (Java Core)** | `api-gateway` (`#1`), `product-service`, `order-service`, `inventory-service`, `payment-service` | OS/K3s Agent: `450 MiB` + Gateway (`200 MiB`) + 4 Java 21 Services (`4 × 450 MiB = 1.8 GiB`) = **`~2.45 GiB`** (`~1.35 GiB` headroom) |
| **VM-3** | **Stateless Worker Node B (.NET, AI & UI)** | `api-gateway` (`#2`), `customer-service`, `promotion-service` (`×2` during Flash Sale), `notification-service`, `ai-agent-service`, `frontend` | OS/K3s Agent: `450 MiB` + 4 .NET Pods (`4 × 220 MiB = 880 MiB`) + Python AI (`450 MiB`) + Frontend NGINX (`64 MiB`) = **`~1.85 GiB`** (`~1.95 GiB` headroom) |
| **VM-4** | **Stateful Data Plane Node** | `PostgreSQL 17` (`7` isolated DBs + `pgvector`), `Redis 7.4`, `Apache Kafka 3.8 (KRaft)`, `MinIO`, `Mailpit` | OS/K3s Agent: `450 MiB` + Postgres (`512 MiB`) + Redis (`300 MiB`) + Kafka KRaft (`768 MiB`) + MinIO/Mailpit (`300 MiB`) = **`~2.33 GiB`** (`~1.47 GiB` OS page-cache headroom) |
| **VM-5** *(or split across VM-1/VM-3 if 4 VMs)* | **Observability & Chaos Node** | `OpenTelemetry Collector`, `Prometheus`, `Grafana`, `Loki`, `Tempo` | OS/K3s Agent: `450 MiB` + OTel (`200 MiB`) + Prometheus (`512 MiB`) + Grafana (`200 MiB`) + Loki (`256 MiB`) + Tempo (`256 MiB`) = **`~1.87 GiB`** |

---

## 2. `K3s` Initial Bootstrap & `kubeadm` Migration Contract (`Q3 — ACCEPTED`)

### 2.1 Phase 1 (`M6`): `K3s` Bootstrap with Standard Upstream Add-ons
To ensure our `K3s` cluster behaves identically to an upstream `kubeadm` cluster:
```bash
# On VM-1 (Control Plane):
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable traefik \
  --disable servicelb \
  --flannel-backend=none \
  --disable-network-policy \
  --write-kubeconfig-mode 644" sh -
```
We then install:
1. **Calico CNI (or Cilium / Canal)** for standard Kubernetes `NetworkPolicy` enforcement.
2. **MetalLB (`L2` ARP Mode)** assigning a dedicated LAN Virtual IP range.
3. **Ingress-NGINX** (`controller.service.type=LoadBalancer`).

### 2.2 Phase 2 (`M6.5 / Post-M6`): Clean Migration Path to `kubeadm`
Because zero `K3s`-specific CRDs are used anywhere in `infrastructure/helm/` or `infrastructure/argocd/`:
1. Drain and reset worker nodes (`k3s-agent-uninstall.sh` / `k3s-uninstall.sh`), backing up StatefulSet volumes (`pg_dump`, MinIO mirror).
2. Provision `containerd` + `kubeadm init --pod-network-cidr=192.168.0.0/16` on VM-1 and `kubeadm join` on VM-2..VM-5.
3. Apply the **exact same** Calico, MetalLB, Ingress-NGINX, StorageClass, and Argo CD root application manifests.

---

## 3. Single-VM Local Development Mode (`M1–M5` Composable Docker Compose)

While working on a single `3.8 GiB` VM during `M1–M5`, running all containers simultaneously is prevented via explicit **Docker Compose Profiles**:

| Profile Flag | Containers Started | Estimated RAM | Target Milestone |
| :--- | :--- | :--- | :--- |
| `--profile infra` | `postgres` (`pg17+pgvector`), `redis`, `kafka` (`KRaft`), `minio`, `mailpit` | `~1.25 GiB` | `M1–M5` |
| `--profile core` | Adds `api-gateway`, `customer-service`, `product-service`, `order-service` | `+1.15 GiB` | `M2` |
| `--profile distributed` | Adds `inventory-service`, `notification-service` | `+0.65 GiB` | `M3` |
| `--profile flash-sale` | Adds `promotion-service`, `payment-service` | `+0.65 GiB` | `M4` |
| `--profile ai` | Adds `ai-agent-service` | `+0.35 GiB` | `M5` |
| `--profile observability` | Adds `otel-collector`, `prometheus`, `grafana`, `loki`, `tempo` | `+1.10 GiB` | `M6–M7` |

*(For detailed Kubernetes probes, HPA, PDB, and the 10 reproducible infrastructure failure scenarios `FAIL-01` through `FAIL-10`, see [`docs/architecture/DEPLOYMENT_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/DEPLOYMENT_ARCHITECTURE.md)).*
