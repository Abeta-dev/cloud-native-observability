# Contributing to cloud-native-observability

Thank you for your interest in contributing to `cloud-native-observability`!

This repository provides production-ready, standardized observability infrastructure blueprints across Docker Compose, Kubernetes (Helm), ArgoCD GitOps, and Terraform. We welcome contributions ranging from bug fixes and documentation enhancements to new OpenTelemetry pipelines and alert rules.

To maintain production reliability across heterogeneous platforms, this project enforces automated verification gates and rigorous engineering standards. Please review this guide before submitting issues or pull requests.

---

## 1. Ground Rules & Maintainer Expectations

Every contribution must satisfy four foundational principles:

### A. Truth-Gate Protocol
- **Zero Phantom Telemetry**: Every metric referenced in Grafana dashboards, every alert query in Prometheus or Alertmanager, and every SLI formula must be validated against real telemetry sources exported by services or OpenTelemetry collectors.
- **Fact-Based Claims**: Documentation and commit messages must avoid unverified superlatives, unmeasured recovery time claims, or speculative architecture topologies.
- **Dashboard Integrity**: All Grafana panel queries are statically validated against the repository's metric catalog during CI.

### B. Canonical SLI AST Equivalence
- The availability error-rate Service Level Indicator (SLI) is single-sourced in `deploy/slo/canonical_sli.promql`:
  ```promql
  (sum(rate(http_requests_total{status=~"5.."}[{{WINDOW}}])) or vector(0)) / (sum(rate(http_requests_total[{{WINDOW}}])) > 0) or vector(0)
  ```
- **Abstract Syntax Tree (AST) Validation**: Any modification to availability alerts in Docker Compose (`deploy/docker-compose/prometheus/alerts.yml`), Kubernetes PrometheusRules (`deploy/kubernetes/alerts/slo-alerts.yaml`), or Terraform alert definitions (`deploy/terraform/modules/grafana_provisioning/alerts.tf`) must strictly match the canonical AST structure parsed by `./scripts/check_version.sh`.
- **Exclusion of 4xx Client Faults**: Availability error rates evaluate server unreliability only (`status=~"5.."`). Client-side errors (`4xx`) must never consume the service error budget.

### C. Zero Hardcoded Credentials
- Manifests, Compose files, and Terraform modules must contain **zero plaintext secrets**, API tokens, or hardcoded passwords.
- All secrets must be externalized using Kubernetes Secrets, Helm values overrides, `.env` files (gitignored), or secret managers (e.g. AWS Secrets Manager, HashiCorp Vault).

### D. Runbook Completeness
- Every newly introduced or modified alert rule must map directly to an actionable Standard Operating Procedure (SOP) in `docs/RUNBOOKS.md`, providing triage steps, diagnostic queries, and mitigation actions for on-call engineers.

---

## 2. Repository Structure

Understanding where files live helps you target your contributions accurately:

```text
cloud-native-observability/
├── .github/
│   ├── ISSUE_TEMPLATE/            # GitHub issue forms (bugs, features, alert rules)
│   ├── workflows/                 # GitHub Actions CI/CD (ci.yml, release.yml, pages.yml)
│   └── PULL_REQUEST_TEMPLATE.md   # Quality & truth-gate verification checklist
├── deploy/
│   ├── docker-compose/            # Local developer sandbox (LGTM stack + OTel + Demo App)
│   │   ├── grafana/               # Provisioned datasources and dashboards
│   │   ├── loki/                  # Local Loki configuration
│   │   ├── otel-collector/        # OTel collector pipeline (OTLP receiver, processors, exporters)
│   │   ├── prometheus/            # Prometheus configuration, alert rules, and alert tests
│   │   └── tempo/                 # Tempo tracing engine configuration
│   ├── kubernetes/                # Production Kubernetes deployment blueprints
│   │   ├── alerts/                # PrometheusRule CRDs and Alertmanager configs
│   │   │   ├── rules/             # Pure Prometheus rules synced from CRDs
│   │   │   └── tests/             # Promtool unit test suites
│   │   ├── argocd/                # GitOps Application & ApplicationSet definitions
│   │   └── helm/                  # Helm chart values (kube-prometheus-stack, etc.)
│   ├── slo/                       # Canonical SLI PromQL source of truth
│   └── terraform/                 # Infrastructure as Code (AWS EKS, Helm, Grafana)
│       ├── environments/          # Environment specifications (dev, prod)
│       └── modules/               # Reusable modules (eks, kubernetes_stack, grafana_provisioning)
├── docs/                          # Architecture documentation, ADRs, and runbooks
│   ├── adr/                       # Architectural Decision Records
│   ├── CLUSTERED_OBSERVABILITY.md # Clustered architecture and scaling topologies
│   ├── RUNBOOKS.md                # Incident response runbooks for all alerts
│   ├── SLO_DESIGN.md              # SRE error budget and multi-burn-rate mathematical framework
│   └── TERRAFORM_GUIDE.md         # Terraform provisioning workflows
└── scripts/                       # Verification gates and test runners
    ├── check_tag_readiness.sh     # Pre-release tag readiness verification
    ├── check_version.sh           # Core truth-gate & AST synchronization verifier
    └── test_alerts.sh             # Promtool alert test runner & CRD sync
```

---

## 3. Development Setup & Required Tooling

To run the local observability stack and execute verification suites, install the following tools:

| Tool | Minimum Version | Purpose |
|---|---|---|
| **Docker & Docker Compose** | Compose v2.20+ | Running local LGTM stack and demo workloads |
| **Prometheus (`promtool`)** | v2.50+ | Unit testing Prometheus alerting and recording rules |
| **Terraform** | v1.5+ | Infrastructure as Code linting, formatting, and validation |
| **TFLint** | v0.51.1+ | Static analysis and best practice enforcement for Terraform |
| **yamllint** | Python 3.10+ | YAML formatting and schema compliance |
| **kubeconform** | v0.6.0+ | Strict Kubernetes schema validation for manifests and CRDs |
| **amtool** (optional) | v0.27+ | Alertmanager configuration syntax and routing verification |

### Installing Tooling on macOS (Homebrew)
```bash
brew install docker docker-compose
brew install prometheus
brew install terraform
brew install tflint
brew install yamllint
brew install kubeconform
```

### Installing Tooling on Linux (Debian/Ubuntu)
```bash
# Docker Compose
sudo apt-get update && sudo apt-get install -y docker-compose-plugin

# Terraform
sudo apt-get install -y gnupg software-properties-common
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# TFLint & Kubeconform
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
curl -L -s https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz -C /usr/local/bin kubeconform

# Yamllint
pip install yamllint
```

---

## 4. Step-by-Step Local Verification Commands

Before opening a pull request or pushing tags, run the complete local verification suite to ensure zero errors.

### Step 1: Version & Truthfulness Gate
Validates version synchronizations between `CHANGELOG.md`, `README.md`, Git tags, and ArgoCD manifests. Checks for unverified claims, validates dashboard PromQL against the metric catalog, verifies Alertmanager route parity, and executes AST equivalence parsing:
```bash
./scripts/check_version.sh
```

### Step 2: Prometheus Alert Rule Unit Tests
Synchronizes Kubernetes `PrometheusRule` CRD definitions into pure YAML rule sets, validates Kubernetes schemas with `kubeconform`, and executes `promtool test rules` across all test fixtures:
```bash
bash ./scripts/test_alerts.sh
```

### Step 3: Terraform Formatting, Validation & TFLint
Ensures all HCL files follow standard canonical formatting, validates provider blocks, and runs static analysis across all modules:
```bash
# Check formatting
terraform -chdir=deploy/terraform fmt -check -recursive

# Validate syntax
terraform -chdir=deploy/terraform init -backend=false
terraform -chdir=deploy/terraform validate

# Run TFLint static analysis
cd deploy/terraform && tflint --init && tflint --recursive
```

### Step 4: Docker Compose Configuration Validation
Validates Compose service dependencies, volume bindings, and port configurations:
```bash
docker compose -f deploy/docker-compose/docker-compose.yml config --quiet
```

### Step 5: YAML Linting
Validates YAML formatting and indentation against repository rules:
```bash
python3 -m yamllint .
```

### Step 6: Release Readiness Preflight
When preparing a new release tag (e.g. `v0.2.3`), run the pre-release readiness script or make target to verify working tree cleanliness, changelog alignment, and end-to-end verification:
```bash
# Direct script execution
./scripts/check_tag_readiness.sh v0.2.3

# Or via Makefile target
make check-release-readiness TAG=v0.2.3
```

---

## 5. Working with Alerts & SLOs

When modifying or adding alerts:

1. **Adhere to the Google SRE Multi-Window Multi-Burn-Rate Model**:
   - Critical Pager 1h window: **14.4x burn rate** (consumes 2% budget in 1 hour).
   - Critical Pager 6h window: **6.0x burn rate** (consumes 5% budget in 6 hours).
   - Warning Ticket 3d window: **1.0x burn rate** (consumes 10% budget in 3 days).
2. **Always exclude 4xx client errors**:
   - Only HTTP 5xx codes (`status=~"5.."`) reflect genuine platform faults.
3. **Write Promtool Unit Tests**:
   - For Kubernetes rules, add fixtures to `deploy/kubernetes/alerts/tests/`.
   - For Compose rules, add fixtures to `deploy/docker-compose/prometheus/alerts-test.yaml`.
4. **Update Documentation**:
   - Add a triage and mitigation entry in `docs/RUNBOOKS.md`.
   - Ensure the alert contains an annotation: `runbook_url: "https://.../docs/RUNBOOKS.md#<alert-anchor>"`.

---

## 6. Git Workflow & Conventional Commits

### Branching Strategy
1. Always base your work on the latest `main` branch:
   ```bash
   git checkout main
   git pull origin main
   ```
2. Create a focused feature branch using standard prefixes:
   - `feat/<feature-name>`: New capabilities, dashboards, exporters, or blueprints
   - `fix/<bug-name>`: Defect repairs or alert threshold calibrations
   - `docs/<doc-name>`: Documentation updates, runbooks, or guides
   - `refactor/<refactor-name>`: HCL, Helm, or pipeline refactoring without behavior change
   - `ci/<workflow-name>`: CI/CD workflow updates

### Conventional Commit Standards
We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:
```text
<type>(<scope>): <short description in present tense>

[optional body providing technical rationale]

[optional footer referencing issues, e.g. Fixes #123]
```

**Allowed Types**:
- `feat`: A new feature or capability
- `fix`: A bug fix
- `docs`: Documentation updates
- `style`: Formatting changes that do not affect code logic
- `refactor`: Code or configuration change that neither fixes a bug nor adds a feature
- `perf`: Performance optimization (e.g. reducing TSDB ingestion overhead)
- `test`: Adding or correcting tests (e.g. Promtool test cases)
- `ci`: CI/CD workflow changes or build script updates
- `chore`: Maintenance tasks, dependency bumps, or tool configuration

**Allowed Scopes**:
- `compose`: Docker Compose sandbox
- `k8s`: Kubernetes manifests
- `helm`: Helm charts and value overrides
- `argocd`: ArgoCD GitOps applications
- `terraform`: Terraform HCL modules and configurations
- `alerts`: Prometheus alerts and recording rules
- `slo`: Service Level Objectives and canonical SLI expressions
- `otel`: OpenTelemetry Collector configuration
- `dashboards`: Grafana dashboard JSON models
- `runbooks`: Incident response runbooks
- `scripts`: Local and CI verification scripts

**Examples**:
- `feat(alerts): add KubeDeploymentReplicasMismatch warning alert`
- `fix(otel): add memory_limiter processor before batch processor`
- `docs(runbooks): add triage steps for ServiceErrorBudgetBurnRateHigh1h`
- `ci(actions): add pages deployment workflow for documentation portal`

---

## 7. Branch Protection & CI-Gated Release Tags

### Branch Protection Rules
The `main` branch is protected by strict GitHub repository settings:
- Direct pushes to `main` are disabled; all changes must arrive via pull request.
- All status checks defined in `.github/workflows/ci.yml` must pass before merging:
  - Version & claim truthfulness gate
  - Promtool alert rules unit testing
  - Docker Compose syntax validation
  - Terraform fmt, validate, and TFLint
  - Kubeconform Kubernetes schema validation
  - Yamllint YAML syntax validation
- Pull requests require at least one approving code review from a maintainer.
- Commits must maintain a linear history (Squash and Merge or Rebase and Merge).

### Release Tag Protocol
Releases are strictly tied to semantic versioning (`vX.Y.Z`):
1. Maintainers update `CHANGELOG.md` with the new version section and release notes.
2. Update version headers in `README.md` and ArgoCD target revisions as applicable.
3. Validate repository release readiness:
   ```bash
   make check-release-readiness TAG=vX.Y.Z
   ```
4. Once merged to `main`, push the annotated Git tag:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```
5. Pushing a `v*` tag triggers `.github/workflows/release.yml`, which runs preflight verification, builds release tarballs, generates SHA256 checksums, and publishes an official GitHub Release.

---

## 8. Community & Communication

- **Discussions**: Use GitHub Discussions for architectural questions, telemetry design patterns, or troubleshooting.
- **Issue Tracker**: Use GitHub Issues for reproducible bugs and actionable feature proposals.
- **Code of Conduct**: All participants are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md).
- **Security Inquiries**: Report security vulnerabilities privately per our [Security Policy](SECURITY.md).
