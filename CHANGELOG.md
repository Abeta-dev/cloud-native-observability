# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- kubernetes: Relocated unwired cloud-specific overlays (`values-eks.yaml`, `values-gke.yaml`) from `deploy/kubernetes/helm/kube-prometheus-stack/` to `deploy/kubernetes/examples/overlays/` with explicit `TEMPLATE ONLY - NOT WIRED IN BASE` headers detailing cloud prerequisites (EBS CSI/PD StorageClasses, AWS IRSA / GCP Workload Identity, and Thanos secrets).
- otel-collector: Clarified OpenTelemetry sampling strategy overlay contracts in `sampling-strategies.yaml` and `docs/SAMPLING_STRATEGIES.md`, introducing modular Helm overlays (`values-sampling-probabilistic.yaml`, `values-sampling-tail.yaml`) with a dual-pipeline pattern protecting 100% Golden Signals metrics while reducing Tempo trace storage costs.

### Added
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
