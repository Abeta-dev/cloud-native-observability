# Versioning, Stability & Deprecation Policy (`cloud-native-observability`)

`cloud-native-observability` (`v0.4.0`, `Go 1.26.0`) follows **Semantic Versioning 2.0.0 (`SemVer`)** across all observability contracts, Prometheus recording/alerting rules, OpenTelemetry Collector pipelines, ArgoCD GitOps manifests, Terraform modules, and the reference `demo-app` microservice.

---

## 1. Component Maturity & Stability Matrix (`v0.4.0`)

| Layer / Component | Canonical Path | Maturity Tier | Stability Guarantee |
| :--- | :--- | :--- | :--- |
| **Canonical Availability SLI** | `deploy/slo/canonical_sli.promql` | **Stable (`GA`)** | AST-verified across Docker Compose, Kubernetes `PrometheusRule`, and Terraform Grafana Alerting via `./scripts/check_version.sh`. |
| **Google SRE Multi-Window Burn-Rate Alerts** | `deploy/kubernetes/alerts/slo-alerts.yaml` | **Stable (`GA`)** | `14.4x` (1h/5m), `6.0x` (6h/30m), `1.0x` (3d/6h) burn-rate thresholds and `job:http_requests:error_rate_*` recording rules are unit-tested via `promtool` (`./scripts/test_alerts.sh`). |
| **Alertmanager Routing & Inhibition Contract** | `deploy/kubernetes/alerts/alertmanager.yaml` | **Stable (`GA`)** | Single-source parity enforced against `deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml`. |
| **OTel Collector Gateway & Spanmetrics** | `deploy/docker-compose/otel-collector/`, `deploy/kubernetes/helm/otel-collector/` | **Stable (`GA`)** | Exposes `traces_spanmetrics_calls_total` and `traces_spanmetrics_duration_milliseconds_bucket` on `:8889` with `memory_limiter` protection. |
| **Loki TSDB `v13` Structured Metadata** | `deploy/docker-compose/loki/`, `deploy/kubernetes/helm/loki/` | **Stable (`GA`)** | Enforces low-cardinality stream labels (`service`, `level`, `environment`) and high-cardinality structured metadata (`trace_id`, `span_id`, `request_id`). |
| **ArgoCD App-of-Apps GitOps Manifests** | `deploy/kubernetes/argocd/` | **Stable (`GA`)** | All `targetRevision` and raw value URLs are synchronized to `v0.4.0` and validated with `kubeconform` (`6` child applications including `observability-alerts`). |
| **Terraform Observability-as-Code (`OaC`)** | `deploy/terraform/` | **Stable (`GA`)** | Provisions AWS S3 storage, all 4 Helm releases (`kube-prometheus-stack`, `tempo-distributed`, `loki`, `opentelemetry-collector`), and Grafana dashboards/alerts. |
| **Reference Microservice (`demo-app`)** | `deploy/docker-compose/demo-app/` | **Stable (`GA`)** | Pure Go 1.26.0 standard library (`0` external third-party dependencies, enforced by `./scripts/check_leaf_imports.sh`) with `100.0%` statement coverage. |

---

## 2. Strict `N + 2` Deprecation Window Contract

To prevent breaking downstream consumers, dashboards, alert routers, or Go reference implementations:

1. **Two-Minor-Release Deprecation Window (`N + 2`)**: Any deprecated Go symbol, Prometheus recording rule, or Terraform variable introduced in minor release `vX.Y.Z` **must remain functional until at least `vX.(Y+2).0`**.
2. **Canonical Go Deprecation Comment Format**: Enforced automatically by `./scripts/check_deprecation.sh`:
   ```go
   // Deprecated: Since vX.Y.Z (remove in >= vA.B.C). Use <Replacement> instead.
   ```
   where `A > X` or (`A == X` and `B >= Y + 2`).
3. **Telemetry Metric & Recording Rule Continuity**: Metric names in the exported catalog (`http_requests_total`, `http_request_duration_seconds_bucket`, `traces_spanmetrics_calls_total`, `traces_spanmetrics_duration_milliseconds_bucket`, `job:http_requests:error_rate_*`) and Grafana dashboard UIDs are verified on every commit by `./scripts/check_version.sh`.

---

## 3. Release Verification Checklist

Every release tag (`v0.4.0`) must pass all automated repository truth gates before publication:

```bash
./scripts/check_secrets.sh
./scripts/check_leaf_imports.sh
./scripts/check_deprecation.sh
./scripts/check_version.sh
./scripts/test_alerts.sh
(cd deploy/docker-compose/demo-app && go test -race -cover ./...)
```
