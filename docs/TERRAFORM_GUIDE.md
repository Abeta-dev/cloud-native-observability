# Comprehensive Guide: Observability as Code with Terraform

This guide details the architectural philosophy, deployment patterns, and operational practices for managing enterprise cloud-native observability using Terraform and OpenTofu.

---

## 1. Architectural Philosophy: Why Observability as Code?

Traditional observability architectures suffer from the **"ClickOps Paradox"**:
1. During steady-state, engineers build ad-hoc dashboards and alert rules via the Grafana UI.
2. During high-stress production incidents, engineers realize that:
   - Staging alert rules do not match Production alert rules.
   - Dashboards were edited during an outage by a teammate and not documented.
   - PagerDuty notification channels fail due to expired or mismatched API tokens.
   - Rebuilding the monitoring cluster after a disaster takes days of manual configuration.

**Observability as Code (OaC)** solves this by treating every dashboard, alert rule, threshold calculation, and data source as version-controlled software:
- **Peer-Reviewed Changes**: Every alert threshold modification requires a Pull Request review.
- **Speculative Plan Verification**: CI automatically generates a `terraform plan` to prevent accidental deletion of critical production alerts.
- **Environment Symmetry**: `dev`, `staging`, and `prod` share identical dashboard layouts and alert logic.
- **Instant Disaster Recovery**: Full telemetry reconstitution in under 3 minutes.

---

## 2. When, Where, and Why Decision Matrix

### When to Use
- **Production Kubernetes Deployments**: Standardizing monitoring across multi-tenant or multi-cluster environments.
- **High-Velocity Microservice Teams**: Enabling teams to declare their own SLIs/SLOs in Git rather than filing Jira tickets with SRE.
- **Audit-Regulated Environments**: SOC2, ISO 27001, HIPAA, and PCI-DSS compliance requiring change attribution for alerts.

### Where to Use
- **Cloud Infrastructure Layer**: Provisioning AWS S3 buckets (or GCP Cloud Storage / Azure Blob) for long-term OpenTelemetry trace storage (Tempo) and log chunks (Loki) with automated lifecycle tiering (Standard → Infrequent Access → Expiration).
- **Orchestration Layer**: Deploying Prometheus Operator, Alertmanager, Tempo, and Loki using the Helm provider.
- **Visualization & Alerting Layer**: Deploying Grafana Dashboards, Data Sources, and Alert Rules using the `grafana/grafana` provider.

### Tradeoffs Comparison
```
                           Speed to First Metric vs Long-Term Maintainability
     Low Maintainability                                            High Maintainability
    ◄──────────────────────────────────────────────────────────────────────────────────►
      Manual ClickOps        Raw Helm CLI         Custom Scripts      Terraform / OpenTofu
      (Fastest first graph,  (Fast cluster setup, (Brittle, custom    (Declarative state,
       brittle drift)         no SaaS state)       maintenance debt)   auditable GitOps)
```

---

## 3. Terraform Module Structure

The observability Terraform codebase is partitioned into three decoupled tiers:

```
cloud-native-observability/
└── deploy/
    └── terraform/
        ├── main.tf                    # Root composition
        ├── variables.tf               # Environment, retentions, credentials
        ├── outputs.tf                 # Bucket names, URLs, UIDs
        ├── versions.tf                # Provider version constraints
        └── modules/
            ├── storage/               # AWS S3 buckets, SSE encryption, lifecycle rules
            ├── kubernetes_stack/      # Helm charts: kube-prometheus-stack, Tempo, Loki
            └── grafana_provisioning/  # Grafana DataSources, Dashboards, Alert Rules
```

---

## 4. Observability as Code Walkthrough

### Provisioning the Golden Signals Dashboard
The Google SRE Golden Signals (Traffic, Latency, Errors, Saturation) dashboard is defined in JSON and provisioned immutably:

```hcl
resource "grafana_dashboard" "golden_signals" {
  folder      = grafana_folder.observability.uid
  config_json = file("${path.module}/files/microservice-golden-signals.json")
  overwrite   = true
}
```

### Defining Alert Rules in Terraform
Alerts are declared directly in HCL with explicit severity labels, runbook links, and evaluation intervals:

```hcl
resource "grafana_rule_group" "golden_signal_rules" {
  name             = "Microservice Golden Signal Alerts"
  folder_uid       = grafana_folder.observability.uid
  interval_seconds = 60

  rule {
    name           = "HighErrorRateP1"
    condition      = "B"
    for            = "2m"
    no_data_state  = "NoData"
    exec_err_state = "Error"

    annotations = {
      summary     = "Microservice HTTP error rate exceeded 5%"
      description = "Microservice error rate is currently {{ $values.B.Value }}% which exceeds the 5% SLO threshold."
      runbook_url = "https://github.com/umesh0492/cloud-native-observability/blob/main/docs/RUNBOOKS.md#high-error-rate"
    }

    labels = {
      severity = "critical"
      tier     = "tier-1"
      team     = "platform-sre"
    }

    data {
      ref_id         = "A"
      datasource_uid = "prometheus"
      model = jsonencode({
        expr    = "(sum(rate(http_requests_total{status=~\"[45]..\"}[1m])) / sum(rate(http_requests_total[1m]))) * 100"
        instant = true
        refId   = "A"
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "-100" # Grafana Expression Engine
      model = jsonencode({
        expression = "A"
        type       = "threshold"
        conditions = [{
          evaluator = { params = [5], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { params = [], type = "last" }
          type      = "query"
        }]
      })
    }
  }
}
```

---

## 5. Secrets Management & Zero-Trust Security

Never commit plain-text credentials (`grafana_auth`, `pagerduty_service_key`, `slack_webhook_url`) to version control.

### Recommended Secret Injection Patterns
1. **Environment Variables**:
   ```bash
   export TF_VAR_grafana_auth="glsa_my_service_account_token_here"
   export TF_VAR_pagerduty_service_key="pd_live_integration_key"
   terraform apply
   ```
2. **HashiCorp Vault / AWS Secrets Manager**:
   ```hcl
   data "aws_secretsmanager_secret_version" "grafana" {
     secret_id = "prod/observability/grafana"
   }
   locals {
     grafana_creds = jsondecode(data.aws_secretsmanager_secret_version.grafana.secret_string)
   }
   provider "grafana" {
     url  = var.grafana_url
     auth = local.grafana_creds.service_account_token
   }
   ```
3. **Mozilla SOPS (Encrypted `secrets.enc.yaml`)**:
   Use `terraform-provider-sops` to decrypt committed secrets at runtime using AWS KMS or age keys.

---

## 6. Disaster Recovery Runbook

If the observability infrastructure is compromised or terminated:
1. **Re-initialize Terraform Backend**:
   ```bash
   cd deploy/terraform
   terraform init -backend-config="bucket=company-tf-state"
   ```
2. **Execute Speculative Plan**:
   ```bash
   terraform plan -out=dr-plan
   ```
3. **Apply and Reconstitute**:
   ```bash
   terraform apply dr-plan
   ```
4. **Validation**:
   - Access Grafana at `http://<grafana-ingress>/d/microservice-golden-signals`
   - Verify Prometheus targets are `UP`
   - Verify Alertmanager contact points route test notifications successfully.
