## Summary
<!-- Briefly describe the observability, SLO, GitOps, or IaC changes proposed in this Pull Request. -->

## Related Issue
<!-- Fixes #(issue) or Relates to #(issue) -->

## Type of Change
- [ ] `feat`: New telemetry pipeline, dashboard, SLO alert rule, or Terraform/Helm capability
- [ ] `fix`: PromQL/Alertmanager fix, Collector config fix, or manifest remediation
- [ ] `docs` / `skills`: Documentation, `docs/index.html`, `llms.txt`, `RUNBOOKS.md`, or `skills/*/SKILL.md` update
- [ ] `ci` / `chore`: Workflow hardening, verification gate, or dependency update

## Affected Components
- [ ] **Reference Service**: `deploy/docker-compose/demo-app/` (Go OTel instrumentation & unit tests)
- [ ] **Docker Compose LGTM Sandbox**: `deploy/docker-compose/` (Prometheus, Mimir, Loki, Tempo, Grafana, OTel Collector)
- [ ] **Kubernetes & Helm**: `deploy/kubernetes/` (Charts, values, `PrometheusRule` manifests)
- [ ] **ArgoCD GitOps**: `deploy/kubernetes/argocd/` (App-of-Apps & application manifests)
- [ ] **Terraform IaC**: `deploy/terraform/` (AWS/Kubernetes stack & Grafana provisioning modules)
- [ ] **SLO & Alerting**: `deploy/slo/canonical_sli.promql` · `deploy/*/alerts/` (Google SRE multi-window burn-rate alerts)
- [ ] **Docs, Portal & AI Skills**: `docs/` · `docs/index.html` · `llms.txt` · `AGENTS.md` · `skills/` · `.github/workflows/`

## Mandatory Quality, Telemetry & Security Gates
- [ ] `./scripts/check_secrets.sh` passed with **0 leaked credentials or verified TruffleHog findings**.
- [ ] `./scripts/check_version.sh` passed (`vMAJOR.MINOR.PATCH` parity, ArgoCD revision sync, PromQL dashboard catalog verification, Alertmanager parity, Canonical SLI AST equivalence, and truthfulness gate).
- [ ] `bash ./scripts/test_alerts.sh` passed (Kubeconform schema validation + `promtool` rule & unit tests).
- [ ] `(cd deploy/docker-compose/demo-app && go test -race -cover ./...)` passed with **100.0% statement coverage** and **0 data races**.
- [ ] **Terraform & Alertmanager Lint** (when touched): `amtool check-config deploy/kubernetes/alerts/alertmanager.yaml`, `terraform -chdir=deploy/terraform fmt -check -recursive`, `terraform validate`, and `tflint --recursive` pass cleanly.
- [ ] **Canonical Availability SLI AST Equivalence**: Availability error-rate queries strictly match `deploy/slo/canonical_sli.promql` (`status=~"5.."`, excluding 4xx client errors).
- [ ] **Runbook & AI Context Sync**: All modified alerts have an incident SOP in `docs/RUNBOOKS.md`, and `README.md`, `CHANGELOG.md`, `docs/index.html`, `docs/llms.txt` (`llms.txt`), `AGENTS.md`, and `skills/*/SKILL.md` remain synchronized.
