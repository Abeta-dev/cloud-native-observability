# Contributing to cloud-native-observability

Thank you for your interest in contributing to `cloud-native-observability`!

This repository provides production-ready, standardized observability infrastructure blueprints across Docker Compose, Kubernetes (Helm), ArgoCD GitOps, and Terraform.

---

## 1. Ground Rules & Maintainer Expectations

`cloud-native-observability` adheres to strict automated verification gates:
- **Truth-Gate Protocol**: Every metric referenced in Grafana dashboards, every alert query in Prometheus/Alertmanager, and every SLI formula must be validated against actual telemetry sources.
- **Canonical SLI Equivalence**: The availability error-rate SLI is single-sourced in `deploy/slo/canonical_sli.promql` and AST-verified across Compose alerts, Kubernetes SLO rules, and Terraform alert resources.
- **Zero Hardcoded Secrets**: All credentials and sensitive tokens must use Kubernetes secrets or environment variables.

---

## 2. Development Setup & Prerequisites

### Required Tooling
- **Docker & Docker Compose**: Compose v2.20+
- **Prometheus Tool (`promtool`)**: v2.50+
- **Terraform**: v1.5+
- **yamllint**: Python yamllint
- **kubeconform**: Strict Kubernetes schema validator

### Verification Suite
Before submitting any changes, run the full verification suite locally:

```bash
# 1. Version & Telemetry Synchronization Gate
./scripts/check_version.sh

# 2. Prometheus Alert Rule Validation
bash ./scripts/test_alerts.sh

# 3. Docker Compose Configuration Lint
docker compose -f deploy/docker-compose/docker-compose.yml config --quiet

# 4. Terraform Formatting & Validation
terraform -chdir=deploy/terraform fmt -check -recursive
terraform -chdir=deploy/terraform init -backend=false
terraform -chdir=deploy/terraform validate

# 5. YAML Linting
python3 -m yamllint .
```

---

## 3. Pull Request Guidelines

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
2. Ensure all 5 verification checks above pass with exit code 0.
3. Keep commits atomic with conventional commit messages (`feat:`, `fix:`, `docs:`, `refactor:`, `ci:`).
4. Open a pull request describing the changes and linking relevant issues.
