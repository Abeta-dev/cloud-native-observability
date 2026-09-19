## Summary

<!-- Briefly describe the changes proposed in this Pull Request and their architectural justification. -->

## Affected Components

- [ ] Docker Compose Local Sandbox (`deploy/docker-compose/`)
- [ ] Kubernetes Manifests / Helm Charts (`deploy/kubernetes/`)
- [ ] ArgoCD GitOps Definitions (`deploy/kubernetes/argocd/`)
- [ ] Terraform Infrastructure as Code (`deploy/terraform/`)
- [ ] Prometheus Alert Rules & SLO Definitions (`deploy/*/alerts/`, `deploy/slo/`)
- [ ] Grafana Dashboards (`deploy/*/grafana/dashboards/`)
- [ ] OpenTelemetry Collector Pipeline (`deploy/*/otel-collector/`)
- [ ] Incident Runbooks & Architecture Docs (`docs/`, `README.md`)

---

## Strict Quality & Truth-Gate Checklist

Before requesting maintainer review, please verify that all automated verification gates pass locally:

- [ ] **Version Synchronization**: `./scripts/check_version.sh` passes with exit code 0 (validating version tags, ArgoCD sync, and truthfulness gates).
- [ ] **Promtool Alert Unit Tests**: `bash ./scripts/test_alerts.sh` passes with exit code 0 (all test fixtures succeed).
- [ ] **Alertmanager Config Lint**: `amtool check-config deploy/kubernetes/alerts/alertmanager.yaml` passes without syntax or route errors.
- [ ] **Terraform Formatting & Validation**: `terraform -chdir=deploy/terraform fmt -check -recursive` and `terraform -chdir=deploy/terraform validate` succeed.
- [ ] **Terraform Linting**: `tflint --recursive` passes inside `deploy/terraform` with zero rule violations.
- [ ] **Canonical Availability SLI AST Equivalence**: Any new or updated availability error-rate expression matches `deploy/slo/canonical_sli.promql` and strictly excludes 4xx client status codes (`status=~"5.."`).
- [ ] **Runbook Coverage**: All new or modified alerts have a dedicated triage and mitigation SOP documented in [docs/RUNBOOKS.md](file:///Users/umesh/Documents/go-backend-libraries/cloud-native-observability/docs/RUNBOOKS.md).
- [ ] **Zero Hardcoded Credentials**: No secrets, tokens, or plaintext credentials exist in manifests or configuration files.

---

## Verification Evidence

<!-- Paste terminal output or test logs demonstrating that the verification suite passed locally. -->

```shell
# Paste output of:
# ./scripts/check_version.sh
# bash ./scripts/test_alerts.sh
# terraform -chdir=deploy/terraform fmt -check -recursive
# cd deploy/terraform && tflint --recursive
```

---

## Related Issues

<!-- Closes #123 / Fixes #456 -->
Fixes #
