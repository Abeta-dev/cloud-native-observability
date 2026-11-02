---
name: cno-gitops-terraform
description: Kubernetes Kustomize overlays (local, EKS, GKE), ArgoCD App-of-Apps GitOps deployment, and Terraform Observability-as-Code provisioning for github.com/Abeta-dev/cloud-native-observability (v0.2.4).
---

# `cno-gitops-terraform` Subskill (`v0.2.4`)

Key paths:
- `deploy/kubernetes/base/`
- `deploy/kubernetes/overlays/{local,eks,gke}/`
- `deploy/kubernetes/argocd/`
- `deploy/terraform/`

## 1. Kubernetes Kustomize Base & Cloud Overlays (`deploy/kubernetes/`)

- **`deploy/kubernetes/base/`**: Contains namespace-scoped (`observability`) manifests for OTel Collector, Prometheus, Alertmanager, Loki, Tempo, and Grafana with non-root `securityContext`, resource requests/limits, and readiness/liveness probes.
- **Overlays**:
  - `overlays/local`: Kind / Minikube / Docker Desktop development profile with reduced replicas and local `emptyDir` / standard PVC storage.
  - `overlays/eks`: AWS EKS production profile (`gp3` StorageClass, IRSA annotations for S3-backed Loki/Tempo object storage).
  - `overlays/gke`: Google Cloud GKE production profile (`premium-rwo` StorageClass, Workload Identity annotations for GCS object storage).

Validate Kustomize builds before committing:
```bash
kubectl kustomize deploy/kubernetes/overlays/local > /dev/null
kubectl kustomize deploy/kubernetes/overlays/eks > /dev/null
kubectl kustomize deploy/kubernetes/overlays/gke > /dev/null
```

## 2. ArgoCD GitOps App-of-Apps (`deploy/kubernetes/argocd/`)

- `project.yaml` defines the restricted `observability` `AppProject` with least-privilege cluster/namespace destinations.
- `root-app.yaml` bootstraps child `Application` manifests (`apps/*.yaml`) ordered by `argocd.argoproj.io/sync-wave` so storage and collectors initialize before dashboards and alerting rules.

## 3. Terraform Observability-as-Code (`deploy/terraform/`)

- `main.tf`, `variables.tf`, `dashboards.tf`, `alerts.tf`, and `outputs.tf` provision Grafana folders, datasources, dashboards, and unified alerting rules declaratively via the `grafana/grafana` Terraform provider.
- **SLI Parity Rule**: Any modification to the availability error-rate expression in `deploy/terraform/alerts.tf` must remain AST-identical to `configs/prometheus/rules/recording_rules.yml` and `configs/grafana/dashboards/service-golden-signals.json`, verified by `./scripts/check_version.sh`.
