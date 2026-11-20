# AGENTS.md — `cloud-native-observability` (`github.com/abeta-dev/cloud-native-observability`)

Production-grade OpenTelemetry + LGTM (`Loki` + `Grafana` + `Tempo` + `Prometheus`) observability blueprint (`v0.4.0`, `Go 1.26.0`) with Google SRE multi-window burn-rate alerting, Kubernetes ArgoCD GitOps overlays, and Terraform Observability-as-Code.

## Skill Routing Table

Load the smallest subskill that matches your task:

| Skill | Path | When to Load |
| :--- | :--- | :--- |
| **`cloud-native-observability` (Umbrella)** | [`skills/cloud-native-observability/SKILL.md`](skills/cloud-native-observability/SKILL.md) | Architecture overview, repository layout, and truth-gate verification (`./scripts/check_secrets.sh`, `./scripts/check_version.sh`, `./scripts/test_alerts.sh`, `100.0%` `demo-app` statement coverage). |
| **`cno-otel-lgtm-stack`** | [`skills/cno-otel-lgtm-stack/SKILL.md`](skills/cno-otel-lgtm-stack/SKILL.md) | OpenTelemetry Collector pipeline (`:4317`/`:4318`) with `spanmetrics` (`traces_spanmetrics_calls_total`, `traces_spanmetrics_duration_milliseconds_bucket` on `:8889`), Prometheus scraping, Loki TSDB `v13` structured metadata, Tempo traces, and Grafana dashboards. |
| **`cno-sre-slo-alerting`** | [`skills/cno-sre-slo-alerting/SKILL.md`](skills/cno-sre-slo-alerting/SKILL.md) | Google SRE multi-window multi-burn-rate alerts (`14.4x`, `6.0x`, `1.0x`), recording rules (`job:http_requests:error_rate_*`), Alertmanager parity, and PromQL AST equivalence gates. |
| **`cno-gitops-terraform`** | [`skills/cno-gitops-terraform/SKILL.md`](skills/cno-gitops-terraform/SKILL.md) | Kubernetes Helm value profiles (`deploy/kubernetes/helm/`) and cloud overlays (`values-eks.yaml`, `values-gke.yaml`), ArgoCD App-of-Apps manifests (`deploy/kubernetes/argocd/`), and Terraform (`deploy/terraform/`) provisioning. |

## Module Code-Owner Agents & Automated PR Review

Every path in `cloud-native-observability` (`v0.4.0`) is mapped via [`.github/CODEOWNERS`](.github/CODEOWNERS) and [`.github/module-agents.json`](.github/module-agents.json) to one of 4 domain-specialized Module Code-Owner Agents (`@umesh0492`), audited automatically on every Pull Request by `./scripts/module_agent_review.sh` and [`.github/workflows/module-agent-review.yml`](.github/workflows/module-agent-review.yml):

| Module Code-Owner Agent | Companion Skill | Owned Paths | Enforced PR Verification Gates |
| :--- | :--- | :--- | :--- |
| **`@cno-otel-lgtm-stack-agent`** | [`skills/cno-otel-lgtm-stack/SKILL.md`](skills/cno-otel-lgtm-stack/SKILL.md) | `/compose.yaml`, `/deploy/docker-compose/`, `/docs/SAMPLING_STRATEGIES.md`, `/docs/INTEGRATION_GUIDE.md`, `/docs/CLUSTERED_OBSERVABILITY.md` | `demo-app` unit & race tests (`100.0%` coverage), OTel Collector `memory_limiter` + `spanmetrics` (`:8889`), Loki TSDB `v13` structured metadata, Grafana dashboard metric catalog validation |
| **`@cno-sre-slo-alerting-agent`** | [`skills/cno-sre-slo-alerting/SKILL.md`](skills/cno-sre-slo-alerting/SKILL.md) | `/deploy/slo/`, `/deploy/kubernetes/alerts/`, `/docs/SLO_DESIGN.md`, `/docs/RUNBOOKS.md`, `/scripts/test_alerts.sh` | Canonical Availability SLI PromQL AST equivalence, Google SRE multi-window burn-rate alerts (`14.4x`, `6.0x`, `1.0x`), Alertmanager standalone/Helm parity, runbook synchronization |
| **`@cno-gitops-terraform-agent`** | [`skills/cno-gitops-terraform/SKILL.md`](skills/cno-gitops-terraform/SKILL.md) | `/deploy/kubernetes/argocd/`, `/deploy/kubernetes/helm-values/`, `/deploy/kubernetes/helm/`, `/deploy/kubernetes/examples/`, `/deploy/kubernetes/overlays/`, `/deploy/kubernetes/secrets/`, `/deploy/kubernetes/network-policies/`, `/deploy/kubernetes/otel-operator/`, `/deploy/terraform/`, `/docs/TERRAFORM_GUIDE.md` | ArgoCD `v0.4.0` revision parity, Helm values & cloud overlays (`values-eks.yaml`, `values-gke.yaml`), Terraform module & Canonical SLI AST equivalence |
| **`@cno-platform-governance-agent`** | [`skills/cloud-native-observability/SKILL.md`](skills/cloud-native-observability/SKILL.md) | `/.github/`, `/scripts/`, `/docs/index.html`, `/docs/llms.txt`, `/docs/adr/`, `/skills/`, `/AGENTS.md`, `/ARCHITECTURE.md`, `/README.md`, `/CHANGELOG.md`, `/llms.txt`, `/Makefile`, `/.yamllint` | `./scripts/check_secrets.sh`, `./scripts/check_version.sh`, SHA-pinned GitHub Actions (`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`), Bash 3.2 syntax, and `yamllint` verification |

Run the local Module Code-Owner Agent review before pushing:

```bash
./scripts/module_agent_review.sh --base origin/main --head HEAD
```

## Mandatory Verification Gates

Before committing or opening a PR in this repository, always run:

```bash
./scripts/check_secrets.sh
./scripts/check_version.sh
./scripts/test_alerts.sh
(cd deploy/docker-compose/demo-app && go test -race -cover ./...)
```

- **Secret & Credential Scanning Gate (`./scripts/check_secrets.sh`)**: Enforces zero tracked key/`.env` files, PEM private key headers, cloud/API tokens, embedded DSN credentials, and verified git history secrets via TruffleHog.
- **Demo App Coverage Gate**: `deploy/docker-compose/demo-app` unit tests must pass `go test -race -cover ./...` with `100.0%` statement coverage.
- **Alertmanager Parity Gate**: `deploy/kubernetes/alerts/alertmanager.yaml` and the `alertmanager.config` section in `deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml` must remain semantically identical.
- **Canonical Availability SLI Gate**: Canonical SLI (`deploy/slo/canonical_sli.promql`), Docker Compose Golden Signals (`deploy/docker-compose/prometheus/alerts.yml`), Kubernetes recording rules (`deploy/kubernetes/alerts/slo-alerts.yaml`), and Terraform SLO modules (`deploy/terraform/modules/grafana_provisioning/alerts.tf`) must use the exact same PromQL AST for HTTP error ratio (`status=~"5.."` over total `http_requests_total`).
- **OTel Spanmetrics Gate**: Always use `traces_spanmetrics_calls_total` and `traces_spanmetrics_duration_milliseconds_bucket` generated by the OpenTelemetry Collector `spanmetrics` connector and exposed on port `:8889`.
