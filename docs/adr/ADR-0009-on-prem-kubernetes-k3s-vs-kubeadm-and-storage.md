# ADR-0009: On-Prem Multi-VM Kubernetes Strategy (`K3s` vs. `kubeadm`), MetalLB & Storage

- **Status:** `PROPOSED`
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
In Milestone `M6`, we deploy the entire platform onto an **on-prem Kubernetes cluster across multiple Linux VMs**. We must evaluate:
1. Cluster distribution: **`K3s`** vs. **`kubeadm`**.
2. Bare-metal LoadBalancer & Ingress: **`MetalLB + Ingress-NGINX`**.
3. Persistent storage for StatefulSets: **`local-path-provisioner` + Node Affinity + Automated Backups** vs. **`Longhorn` distributed block storage**.

## 2. Options Considered
- **Option A (`K3s` with Traefik/ServiceLB disabled + `MetalLB` + `Ingress-NGINX` + `local-path` storage)**: Lightweight CNCF-certified control plane (`~550 MiB` RAM) with standard enterprise ingress/LB components.
- **Option B (`kubeadm` + `containerd` + `Calico` + `MetalLB` + `Ingress-NGINX`)**: Full upstream control-plane administration (`~1.8 GiB` control-plane RAM).
- **Option C (Add `Longhorn` + `Harbor` + `Keycloak` + `OpenSearch` simultaneously on 4 GiB VMs)**.

## 3. Decision
1. **Recommend Option A (`K3s` customized with `MetalLB` + `Ingress-NGINX` + `Calico/Canal NetworkPolicy`)** as the default for VMs with `4–8 GiB` RAM, while keeping all Helm charts, Argo CD apps, and K8s manifests **100% compatible with `kubeadm` (Option B)** so you can choose `kubeadm` if your multi-VM lab has $\ge 8\text{ GiB}$ RAM per node and you want hands-on `kubeadm`/`etcd` bootstrap practice.
2. **Storage**: Default to **`local-path-provisioner` pinned via `nodeAffinity` to the Stateful Worker VM + scheduled `pg_dump`/MinIO snapshot CronJobs** when total cluster RAM is $< 24\text{ GiB}$. Evaluate **Longhorn** only if 3+ worker VMs each have dedicated fast SSDs and $\ge 8\text{ GiB}$ RAM.

## 4. Consequences & Trade-offs
- **Positive**: Preserves `>1.2 GiB` of cluster RAM for application pods and `k6` load testing; exercises real `MetalLB` L2 ARP VIP failover, `Ingress-NGINX` tuning, `NetworkPolicy` isolation, `Helm`, and `Argo CD` GitOps.
- **Negative / Cost**: `local-path` volumes are tied to their host VM (if the stateful VM dies completely, recovery relies on restoring the latest `pg_dump`/MinIO backup rather than automatic storage replica failover—honestly documented per Mandatory Rule #6).

## 5. Rejected Alternatives
- **Option C (Deploying Longhorn + Harbor + OpenSearch + Keycloak all at once on small VMs)**: Consumes `>8 GiB` RAM on infrastructure daemons alone before a single business microservice starts.
