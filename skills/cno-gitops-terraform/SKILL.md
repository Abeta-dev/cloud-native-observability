---
name: cno-gitops-terraform
description: Kubernetes Helm value profiles, cloud overlays (EKS, GKE), ArgoCD App-of-Apps GitOps deployment, and Terraform Observability-as-Code provisioning for github.com/Abeta-dev/cloud-native-observability (v0.3.0).
---

# `cno-gitops-terraform` Subskill (`v0.3.0`)

Key paths:
- `deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml`
- `deploy/kubernetes/helm/otel-collector/values.yaml`
- `deploy/kubernetes/helm/loki/values.yaml`
- `deploy/kubernetes/helm/tempo/values.yaml`
- `deploy/kubernetes/examples/overlays/values-eks.yaml` & `deploy/kubernetes/examples/overlays/values-gke.yaml`
- `deploy/kubernetes/argocd/app-of-apps.yaml` & `deploy/kubernetes/argocd/apps/`
- `deploy/terraform/main.tf`, `deploy/terraform/variables.tf`, `deploy/terraform/outputs.tf`, & `deploy/terraform/modules/`

## 1. Kubernetes Helm Base Values & Cloud Overlays (`deploy/kubernetes/`)

- **Base Helm Values (`deploy/kubernetes/helm/`)**:
  - `deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml`: Prometheus, Alertmanager, and Grafana base configuration.
  - `deploy/kubernetes/helm/otel-collector/values.yaml`: DaemonSet OTel Collector with `memory_limiter`, `k8sattributes`, `spanmetrics`, `servicegraph`, Tempo trace export, and Loki OTLP log export.
  - `deploy/kubernetes/helm/loki/values.yaml`: Scalable TSDB `v13` log storage configuration.
  - `deploy/kubernetes/helm/tempo/values.yaml`: Distributed Tempo tracing configuration.
- **Cloud Provider Overlays (`deploy/kubernetes/examples/overlays/`)**:
  - `deploy/kubernetes/examples/overlays/values-eks.yaml`: AWS EKS production overlay (`gp3` StorageClass, IRSA annotations for S3-backed object storage).
  - `deploy/kubernetes/examples/overlays/values-gke.yaml`: Google Cloud GKE production overlay (`standard-rwo` StorageClass, Workload Identity annotations for GCS object storage).

## 2. ArgoCD GitOps App-of-Apps (`deploy/kubernetes/argocd/`)

- `deploy/kubernetes/argocd/app-of-apps.yaml` bootstraps child `Application` manifests in `deploy/kubernetes/argocd/apps/` (`secrets.yaml`, `kube-prometheus-stack.yaml`, `loki-stack.yaml`, `tempo-stack.yaml`, `otel-collector.yaml`) ordered by `argocd.argoproj.io/sync-wave`.
- Every `targetRevision` and raw GitHub `valueFiles` URL in `deploy/kubernetes/argocd/` must match the canonical release version (`v0.3.0`), enforced by `./scripts/check_version.sh`.

## 3. Terraform Observability-as-Code (`deploy/terraform/`)

- Root configuration (`deploy/terraform/main.tf`, `deploy/terraform/variables.tf`, `deploy/terraform/outputs.tf`) composes three modules:
  - `deploy/terraform/modules/storage/`: S3 bucket lifecycle and encryption for long-term telemetry blocks.
  - `deploy/terraform/modules/kubernetes_stack/`: Declarative Helm release provisioning for Kubernetes monitoring workloads.
  - `deploy/terraform/modules/grafana_provisioning/`: Grafana folders, dashboards (`main.tf`, `files/microservice-golden-signals.json`), and unified alerting rules (`alerts.tf`).
- **SLI Parity Rule**: Any modification to the `HighErrorRateP1` expression in `deploy/terraform/modules/grafana_provisioning/alerts.tf` must remain AST-equivalent to `deploy/slo/canonical_sli.promql`, verified by `./scripts/check_version.sh`.
