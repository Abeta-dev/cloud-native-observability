# Changelog

> **Note on Repository History**: History reconstructed on 2026-09-15; see CHANGELOG.md for the real feature timeline.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-15

Clean-slate architecture: No backward compatibility preserved. Legacy un-versioned metrics, deprecated dashboard schemas, and unwired cloud provider manifests have been purged without backwards-compatibility shims, as no external developers are actively consuming pre-release revisions.

### Changed
- demo-app: Deduplicated worker pool queue metrics, standardizing on `app_workerpool_queue_depth` and `app_workerpool_queue_capacity` with consistent `app_workerpool_*` metric prefixing across demo-app, Prometheus alert rules, Grafana dashboards, and runbooks.
- kubernetes: Relocated unwired cloud-specific overlays (`values-eks.yaml`, `values-gke.yaml`) from `deploy/kubernetes/helm/kube-prometheus-stack/` to `deploy/kubernetes/examples/overlays/` with explicit `TEMPLATE ONLY - NOT WIRED IN BASE` headers detailing cloud prerequisites (EBS CSI/PD StorageClasses, AWS IRSA / GCP Workload Identity, and Thanos secrets).
- otel-collector: Clarified OpenTelemetry sampling strategy overlay contracts in `sampling-strategies.yaml` and `docs/SAMPLING_STRATEGIES.md`, introducing modular Helm overlays (`values-sampling-probabilistic.yaml`, `values-sampling-tail.yaml`) with a dual-pipeline pattern protecting 100% Golden Signals metrics while reducing Tempo trace storage costs.

### Added
- ci: Promoted yamllint rules `line-length`, `truthy`, and `comments-indentation` to error level and fixed all violations.
- ci: Enhanced manifest validation by piping rendered Helm templates through `kubeconform -strict -ignore-missing-schemas` and covering `k8s-node-alerts.yaml` in manifest verification.
- deps: Pinned all GitHub Actions (`actions/checkout@v4.1.7`, `hashicorp/setup-terraform@v3.1.2`, `terraform-linters/setup-tflint@v4.1.1`, `azure/setup-helm@v4.2.0`), TFLint version (`v0.51.1`), and demo-app Dockerfile base images (`golang:1.24.4-alpine`, `alpine:3.19.1`) to explicit minor/patch versions.
- secrets: Added `deploy/kubernetes/secrets/thanos-objstore-secret.yaml.example` template for S3 and GCS Thanos object storage credentials.
- docs: Added `deploy/kubernetes/examples/overlays/README.md` documenting cloud overlay prerequisites, IAM identity mappings, and Helm deployment steps.

## [0.1.0] - 2026-09-09

Initial public release.

### Added
- docker-compose: Local observability sandbox running Prometheus, Grafana, Tempo, Loki, and OpenTelemetry Collector.
- demo-app: Go HTTP service emitting 4 Golden Signals, trace contexts, dropped task counters, and circuit breaker states.
- traffic-generator: POSIX sh traffic script exercising HTTP endpoints and error distributions.
- kubernetes: Helm value overlays for kube-prometheus-stack, Loki, Tempo, and OpenTelemetry Collector.
- argocd: Declarative App-of-Apps GitOps manifests with sync-wave secrets provisioning.
- terraform: Modular AWS and Kubernetes infrastructure definitions for S3 storage, Helm releases, and Grafana provisioning.
- alerts: Prometheus multi-window multi-burn-rate SLO alerting rules with label preservation.
- dashboards: Pre-provisioned Grafana dashboards for RED metrics and log inspection.

### Known limitations
- Local Docker Compose sandbox uses single-binary storage for Tempo and Loki rather than distributed object storage.
- Alertmanager Slack and PagerDuty routes require operator-provided webhook URLs via Kubernetes Secret or environment variables.
- Pre-commit terraform validation requires local terraform CLI and AWS provider credentials.
