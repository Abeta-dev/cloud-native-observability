resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
    labels = {
      name        = var.namespace
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Secret: Grafana Admin Credentials
# -----------------------------------------------------------------------------
resource "random_password" "grafana_admin" {
  count   = var.grafana_admin_password == "" ? 1 : 0
  length  = 24
  special = false
}

locals {
  grafana_password = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.grafana_admin[0].result
}

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = var.grafana_admin_secret_name
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "grafana"
      "app.kubernetes.io/part-of"    = "kube-prometheus-stack"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    admin-user     = "admin"
    admin-password = local.grafana_password
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# Kubernetes Secret: Alertmanager Secrets (Slack & PagerDuty credentials)
# -----------------------------------------------------------------------------
resource "kubernetes_secret" "alertmanager_secrets" {
  metadata {
    name      = "alertmanager-secrets"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "alertmanager"
      "app.kubernetes.io/part-of"    = "kube-prometheus-stack"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    slack-webhook-url     = var.alertmanager_slack_webhook_url != "" ? var.alertmanager_slack_webhook_url : "https://hooks.slack.com/services/DUMMY/WEBHOOK/URL"
    pagerduty-routing-key = var.alertmanager_pagerduty_routing_key != "" ? var.alertmanager_pagerduty_routing_key : "dummy-pagerduty-routing-key-placeholder"
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# Helm: kube-prometheus-stack (Prometheus, Operator, NodeExporter, Alertmanager)
# -----------------------------------------------------------------------------
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.7.1"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  depends_on = [
    kubernetes_secret.grafana_admin,
    kubernetes_secret.alertmanager_secrets
  ]

  values = [
    file("${path.module}/../../../kubernetes/helm/kube-prometheus-stack/values-base.yaml"),
    yamlencode({
      grafana = {
        admin = {
          existingSecret = var.grafana_admin_secret_name
        }
      }
      alertmanager = {
        alertmanagerSpec = {
          retention = var.alertmanager_retention
        }
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# Helm: Grafana Tempo Distributed (Distributed Tracing with S3 backend)
# -----------------------------------------------------------------------------
resource "helm_release" "tempo" {
  name       = "tempo-distributed"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo-distributed"
  version    = "1.9.1"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    yamlencode({
      fullnameOverride = "tempo"
      traces = {
        otlp = {
          grpc = {
            enabled = true
          }
          http = {
            enabled = true
          }
        }
      }
      storage = {
        trace = {
          backend = var.tempo_s3_bucket != "" ? "s3" : "local"
          s3 = var.tempo_s3_bucket != "" ? {
            bucket   = var.tempo_s3_bucket
            endpoint = "s3.${var.aws_region}.amazonaws.com"
            region   = var.aws_region
            insecure = false
          } : null
        }
      }
      compactor = {
        replicas = 1
        config = {
          compaction = {
            compaction_window         = "1h"
            max_block_bytes           = 500000000
            block_retention           = "${var.trace_retention_days * 24}h"
            compacted_block_retention = "2h"
          }
        }
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# Helm: Grafana Loki (Log Aggregation with S3 backend)
# -----------------------------------------------------------------------------
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "5.43.3"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    yamlencode({
      loki = {
        auth_enabled = false
        storage = {
          type = var.loki_s3_bucket != "" ? "s3" : "filesystem"
          s3 = var.loki_s3_bucket != "" ? {
            bucket = var.loki_s3_bucket
            region = var.aws_region
          } : null
        }
      }
    })
  ]
}
