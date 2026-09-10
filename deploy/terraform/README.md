# Cloud-Native Observability as Code (Terraform)

Production-ready Terraform modules and infrastructure compositions for provisioning a complete Google SRE Golden Signals Observability stack: **Prometheus, Grafana, Tempo (Distributed Tracing), Loki (Log Aggregation), and Alertmanager**.

---

## 🧭 Strategic Decision Framework

```
                          ┌────────────────────────────┐
                          │   Observability Request    │
                          └─────────────┬──────────────┘
                                        │
                    ┌───────────────────┴───────────────────┐
                    ▼                                       ▼
        [Ad-Hoc / Exploration]                   [Production / Multi-Env]
        • Temporary debug session               • Audit & Compliance (SOC2)
        • Local laptop spike                    • Multi-cluster consistency
        • Dashboard prototyping                 • Critical On-Call Paging
                    │                                       │
                    ▼                                       ▼
            Manual Grafana UI                       Terraform / IaC
         (ClickOps / Ephemeral)                 (Observability as Code)
```

### 1. When to Use Terraform in Observability
| Scenario | Why Terraform is Essential |
| :--- | :--- |
| **Multi-Environment Promotion** | Promotes identical dashboards, alert rules, and contact points from `dev` → `staging` → `prod` without manual drift. |
| **Audit & Compliance (SOC2 / ISO 27001)** | Mandates that all Alert Rules, PagerDuty on-call escalation, and SLO thresholds undergo Git review, PR approvals, and cryptographic commit signing. |
| **Deterministic Disaster Recovery** | Rebuilds monitoring cluster, metrics pipelines, dashboards, and alerting rules from zero via declarative code if an AWS region or Kubernetes cluster fails. |
| **Microservice Fleet Self-Service** | Allows platform teams to provide reusable Terraform modules so feature teams declare their own SLIs, SLOs, and alert rules alongside their service code. |

---

### 2. Where to Use Terraform in Observability
The stack is partitioned into 3 decoupled layers:

```
┌────────────────────────────────────────────────────────────────────────┐
│  Layer 3: Observability as Code (Grafana Provider)                     │
│  • Prometheus, Tempo & Loki Data Sources                                │
│  • Google SRE Golden Signals Dashboards                                │
│  • P1/P2 Alert Rule Groups & PagerDuty / Slack Routing                 │
├────────────────────────────────────────────────────────────────────────┤
│  Layer 2: Workload Orchestration (Helm & Kubernetes Providers)         │
│  • kube-prometheus-stack (Prometheus Operator, Alertmanager)           │
│  • Grafana Tempo (Distributed Tracing Engine)                          │
│  • Grafana Loki (Log Aggregation DaemonSet)                           │
├────────────────────────────────────────────────────────────────────────┤
│  Layer 1: Resilient Cloud Storage (AWS / S3 Provider)                  │
│  • Tempo Traces Bucket (Lifecycle transition & 30-day retention)       │
│  • Loki Log Chunks Bucket (Standard-IA transition & 90-day retention)  │
│  • Enforced Server-Side Encryption (AES256) & Public Access Block      │
└────────────────────────────────────────────────────────────────────────┘
```

---

### 3. Why Use Terraform (Alternatives Evaluated)

| Approach | Pros | Cons | Why We Chose Terraform |
| :--- | :--- | :--- | :--- |
| **Manual ClickOps (Grafana UI)** | Instant visual feedback for ad-hoc debugging. | Zero version control, silent configuration drift, manual human error during incidents, impossible disaster recovery. | ❌ Strictly forbidden in Staging & Production environments. |
| **Kubernetes ConfigMaps / Helm Values** | Native to Kubernetes cluster. | Scoped only to a single cluster; cannot manage external SaaS (Grafana Cloud, PagerDuty, AWS S3/IAM buckets, Slack webhooks). | ❌ Incomplete cross-system orchestration. |
| **Crossplane** | Kubernetes-native CRDs for cloud resources. | High architectural overhead, requires a separate running Kubernetes control plane to manage infra. | ❌ Heavyweight for standard GitOps CI/CD pipelines. |
| **Terraform / OpenTofu** | Universal declarative ecosystem, state locking, native plan/apply speculative checks in PRs, seamless integration across AWS + K8s + Grafana. | Requires remote state locking (S3/DynamoDB). | ✅ **Industry Standard of Choice**: Unifies cloud storage, IAM, Kubernetes Helm releases, and Grafana Dashboards under one auditable Git repository. |

---

## 📁 Directory Architecture

```
deploy/terraform/
├── README.md                          # Architecture, decision matrices, and execution runbook
├── versions.tf                        # Provider version constraints (Terraform >= 1.5, Grafana, Helm, AWS)
├── variables.tf                       # Validated input parameters (environments, retentions, URLs)
├── terraform.tfvars.example           # Example configuration values
├── main.tf                            # Root composition orchestrating all 3 layers
├── outputs.tf                         # Exported S3 bucket names, namespace, and Grafana dashboard URLs
└── modules/
    ├── storage/                       # Layer 1: S3 Buckets for Traces and Logs
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── kubernetes_stack/              # Layer 2: Helm Releases (Prometheus, Tempo, Loki)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── grafana_provisioning/          # Layer 3: Grafana OaC (Datasources, Dashboards, Alerts)
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── files/
            └── microservice-golden-signals.json
```

---

## 🚀 Step-by-Step Execution Guide

### Prerequisites
- [Terraform](https://www.terraform.io/) `>= 1.5.0` or [OpenTofu](https://opentofu.org/) `>= 1.6.0`
- Access to a Kubernetes cluster (`~/.kube/config`)
- AWS credentials with S3 permissions (if `enable_cloud_storage = "true"`)
- Running Grafana instance or Grafana Cloud Service Account token

### 1. Initialize Working Directory
```bash
cd deploy/terraform
terraform init
```

### 2. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit variables to match your environment
```

### 3. Generate and Inspect Plan
```bash
terraform plan -out=tfplan
```
*Verify that Terraform plans the exact storage buckets, Helm charts, and Grafana alert rules without unexpected destructions.*

### 4. Apply Changes
```bash
terraform apply tfplan
```

---

## 🛡️ CI/CD Automation Pattern (GitHub Actions)

```yaml
name: Observability IaC Pipeline

on:
  pull_request:
    paths:
      - 'deploy/terraform/**'
  push:
    branches: [ main ]
    paths:
      - 'deploy/terraform/**'

jobs:
  terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: deploy/terraform
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Format Check
        run: terraform fmt -check

      - name: Terraform Init
        run: terraform init

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan (Speculative)
        if: github.event_name == 'pull_request'
        run: terraform plan -no-color

      - name: Terraform Apply (Auto-deploy on Merge)
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve
```
