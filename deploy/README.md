# Deployment & Infrastructure Configurations (`deploy/`)

- `local/`: Docker Compose profiles and PostgreSQL 17 isolated multi-database initialization scripts (`ADR-0002`).
- `kubernetes/`: Standard CNCF Kubernetes manifests and Helm charts portable across `K3s` and `kubeadm` (`Q3`, `ADR-0009`).
- `observability/`: OpenTelemetry Collector, Prometheus, Grafana, Loki, and Tempo configurations (`ADR-0011`).
