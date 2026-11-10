# ADR-0009: On-Prem Multi-VM Kubernetes Strategy (`K3s` First on 4–5 VMs, `kubeadm` Migration Path), MetalLB & Storage

- **Status:** `ACCEPTED` (Approved in M0.1 — Q2 3–4 Additional VMs & Q3 Start with K3s, Migrate to kubeadm Later)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Per approved decisions `Q2` and `Q3`:
- **Hardware Topology (`Q2`)**: We can provision **3–4 additional Linux VMs** similar to the current workspace VM (`2 vCPUs`, `~3.8–4 GiB RAM`, `~29 GiB Disk`, `ARM64 aarch64` Ubuntu), giving a **4-to-5 VM cluster (`8–10 vCPUs`, `~15–19 GiB total cluster RAM`)**.
- **Kubernetes Distribution (`Q3`)**: On VMs with `~3.8 GiB` RAM per node, an upstream `kubeadm` control plane consumes `~1.8 GiB` RAM on the master node (`~50%` of node memory), whereas **`K3s`** consumes `~550 MiB`. However, we also want our manifests, networking, and operational runbooks to support a clean migration path to **`kubeadm`** later.

## 2. Options Considered
- **Option A**: Default `K3s` with proprietary Klipper ServiceLB and Traefik v2/v3 CRDs.
- **Option B (Chosen)**: **`K3s` First (with bundled Traefik & ServiceLB disabled so we deploy upstream-standard `MetalLB` + `Ingress-NGINX` + `NetworkPolicies`) across the 4–5 VMs, with a documented `kubeadm` Migration Path (`Q2` & `Q3`)**.
- **Option C**: `kubeadm` only from Day 1.

## 3. Decision (`ACCEPTED`)
1. **Cluster Topology across 4–5 VMs (`Q2 — ACCEPTED`)**:
   - **VM-1 (Dev / Control Plane & GitOps Node)**: Runs `K3s` server (control plane), `Argo CD`, and `k6` load driver.
   - **VM-2 (Stateless Worker Node A)**: Runs `api-gateway`, `promotion-service`, `order-service`, `inventory-service`, `product-service`.
   - **VM-3 (Stateless Worker Node B)**: Runs `api-gateway` (replica 2), `promotion-service` (replica 2), `payment-service`, `customer-service`, `notification-service`, `ai-agent-service`, `frontend`.
   - **VM-4 (Stateful Data Node)**: Dedicated to `PostgreSQL 17`, `Redis 7.4`, `Apache Kafka 3.8 (KRaft)`, and `MinIO` with pinned `nodeAffinity` and local persistent volumes.
   - **VM-5 (Optional Observability Node, or co-located across VM-1/VM-4)**: Runs `OpenTelemetry Collector`, `Prometheus`, `Grafana`, `Loki`, and `Tempo`.
2. **`K3s`-to-`kubeadm` Portability Contract (`Q3 — ACCEPTED`)**:
   - Bootstrap `K3s` with `--disable traefik --disable servicelb` so we install standard upstream **MetalLB (`L2` mode)** and **Ingress-NGINX**.
   - Zero `K3s`-proprietary CRDs (`IngressRoute`, `HelmChartConfig`) may be used in `infrastructure/kubernetes/` or `infrastructure/helm/`. Every manifest uses standard `networking.k8s.io/v1`, `apps/v1`, `autoscaling/v2`, and `policy/v1` APIs so migrating the cluster from `K3s` to `kubeadm` requires **zero changes to application Helm charts or Argo CD manifests**.

## 4. Consequences & Trade-offs
- **Positive**: Fits comfortably within `3.8 GiB` RAM per VM across 4–5 VMs while guaranteeing 100% manifest portability when re-provisioning the cluster with `kubeadm`.
- **Negative / Cost**: Requires disabling K3s built-in ingress/load-balancer flags at install time and installing MetalLB + Ingress-NGINX via Helm.

## 5. Rejected Alternatives
- **Option A (K3s proprietary CRDs)**: Locks manifests to K3s-specific Traefik/Klipper features, obstructing the planned `kubeadm` migration.
