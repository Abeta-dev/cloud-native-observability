# End-to-End Execution Flows — `cloud-native-observability` (`v0.4.0`)

> **Step 3 of the Mandatory Grounding Order** (`AGENTS.md` -> `ARCHITECTURE.md` -> **`docs/FLOWS.md`** -> `skills/*/SKILL.md` -> `docs/CODEGRAPH.md` -> targeted source reads only for verification).

This document traces the five core telemetry, SLO alerting, GitOps, Infrastructure-as-Code, and truth-gate flows across `github.com/abeta-dev/cloud-native-observability` (`v0.4.0`, Go `1.26.0`).

---

## 1. Telemetry Ingestion & Correlation Flow (OTel Collector -> LGTM)

```mermaid
flowchart LR
    App["Instrumented Service\n(demo-app or go-libs service)"] -->|"OTLP gRPC :4317 / HTTP :4318\n(Traces + Structured Logs)"| Lim["OTel Collector\n1. memory_limiter (FIRST)"]
    App -->|"GET /metrics"| Prom["Prometheus\n(App RED + Runtime Metrics)"]
    Lim --> Batch["2. batch processor"]
    Batch -->|Traces| Tempo["Grafana Tempo\n(Distributed Traces)"]
    Batch -->|spanmetrics connector| SpanM["Collector :8889\ntraces_spanmetrics_calls_total\ntraces_spanmetrics_duration_milliseconds_bucket"]
    SpanM -->|Scrape| Prom
    Batch -->|Logs + trace_id/span_id\nas structured metadata| Loki["Grafana Loki\n(TSDB v13)"]
    Prom --> Graf["Grafana 10.4+\n(Unified Exemplars + Trace-to-Logs)"]
    Tempo --> Graf
    Loki --> Graf
```

### Flow Invariants
- **`memory_limiter` is always the first processor** in every OTel Collector pipeline (`traces`, `metrics`, `logs`) to prevent OOM cascades under traffic bursts.
- **Loki TSDB `v13` cardinality guardrail**: High-cardinality IDs (`trace_id`, `span_id`, `request_id`) flow into Loki **structured metadata**, never into indexed stream labels.
- **Spanmetrics contract**: RED latency and call metrics from traces are exported on `:8889` as `traces_spanmetrics_calls_total` and `traces_spanmetrics_duration_milliseconds_bucket`.

---

## 2. Canonical Availability SLI -> Multi-Window Burn-Rate Alerting Flow

```mermaid
flowchart TD
    SLI["deploy/slo/canonical_sli.promql\n(Single Source of Truth HTTP 5xx / Total AST)"] --> RR["1. Recording Rules\njob:http_requests:error_rate_{5m,30m,1h,6h,3d}"]
    RR --> Fast["2a. Critical Fast Burn (14.4x)\n5m AND 1h windows -> Page"]
    RR --> Med["2b. Critical Medium Burn (6.0x)\n30m AND 6h windows -> Page"]
    RR --> Slow["2c. Warning Slow Burn (1.0x)\n6h AND 3d windows -> Ticket/Slack"]
    Fast --> AM["3. Alertmanager Routing\n(deploy/kubernetes/alerts/alertmanager.yaml\n=== Helm values-base.yaml)"]
    Med --> AM
    Slow --> AM
    AM --> RB["4. Incident Triage\n(docs/RUNBOOKS.md)"]
```

- **Cross-deployment AST equivalence**: `./scripts/test_alerts.sh` and `./scripts/check_version.sh` verify that `deploy/slo/canonical_sli.promql`, Docker Compose alerts (`deploy/docker-compose/prometheus/alerts.yml`), Kubernetes alerts (`deploy/kubernetes/alerts/slo-alerts.yaml`), and Terraform alerts (`deploy/terraform/modules/grafana_provisioning/alerts.tf`) share the exact same canonical error-ratio PromQL AST.

---

## 3. Kubernetes GitOps Delivery Flow (ArgoCD App-of-Apps + Helm Overlays)

1. Root application [`deploy/kubernetes/argocd/app-of-apps.yaml`](../deploy/kubernetes/argocd/app-of-apps.yaml) tracks release tag `v0.4.0`.
2. Child `Application` manifests under `deploy/kubernetes/argocd/apps/` reconcile:
   - `kube-prometheus-stack` (Prometheus, Alertmanager, Grafana)
   - `loki`, `tempo`, `opentelemetry-collector`
   - `observability-alerts` (SLO recording rules, burn-rate alerts, Alertmanager config)
3. Each chart layers base values (`deploy/kubernetes/helm/*/values-base.yaml`) with cloud-specific overlays (`values-eks.yaml`, `values-gke.yaml`) and strict `NetworkPolicy` isolation (`deploy/kubernetes/network-policies/`).

---

## 4. Three-Layer Terraform Observability-as-Code Flow (`deploy/terraform/`)

1. **`modules/storage`**: Provisions S3 / GCS object storage buckets and IAM/workload-identity bindings for Loki chunks, Tempo blocks, and Thanos/Prometheus long-term storage.
2. **`modules/kubernetes_stack`**: Deploys Helm releases (Prometheus stack, Loki, Tempo, OpenTelemetry Collector) referencing storage module outputs.
3. **`modules/grafana_provisioning`**: Provisions Grafana folders, 4 validated dashboards (`microservice-golden-signals`, `microservice-apm`, `logs-explorer`, `platform-overview`), and canonical SLO alert rules (`alerts.tf`).

---

## 5. Pre-Commit & CI Truth-Gate Verification Flow

1. `./scripts/check_secrets.sh` — TruffleHog verified git history + static secret/DSN scan.
2. `./scripts/check_leaf_imports.sh` — Confirms `deploy/docker-compose/demo-app` remains 100% pure Go standard library (`0` third-party dependencies).
3. `./scripts/check_deprecation.sh` — Enforces strict `N + 2` deprecation window formatting.
4. `./scripts/check_version.sh` — Validates `v0.4.0` parity across `README.md`, `CHANGELOG.md`, `AGENTS.md`, `skills/*/SKILL.md`, ArgoCD manifests, Grafana dashboard metric catalogs, and documentation claims.
5. `./scripts/test_alerts.sh` — Validates PromQL AST equivalence and Alertmanager standalone/Helm parity.
6. `(cd deploy/docker-compose/demo-app && go test -race -cover ./...)` — Enforces `100.0%` statement coverage with zero data races.
