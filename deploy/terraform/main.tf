# =============================================================================
# Root Observability as Code Composition
# =============================================================================

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth
}

# 1. Long-Term Cloud Storage for Traces and Logs (S3)
module "storage" {
  count  = var.enable_cloud_storage == "true" ? 1 : 0
  source = "./modules/storage"

  project_name         = var.project_name
  environment          = var.environment
  trace_retention_days = var.trace_retention_days
  log_retention_days   = var.log_retention_days
}

# 2. Kubernetes Helm Releases (kube-prometheus-stack, Tempo, Loki)
module "kubernetes_stack" {
  source = "./modules/kubernetes_stack"

  namespace       = var.kubernetes_namespace
  environment     = var.environment
  aws_region                 = var.aws_region
  tempo_s3_bucket            = var.enable_cloud_storage == "true" ? module.storage[0].tempo_bucket_name : ""
  loki_s3_bucket             = var.enable_cloud_storage == "true" ? module.storage[0].loki_bucket_name : ""
  grafana_admin_password     = var.grafana_admin_password
  grafana_admin_secret_name  = var.grafana_admin_secret_name
  trace_retention_days       = var.trace_retention_days
}

# 3. Grafana Observability as Code (Datasources, Dashboards, Alert Rules, PagerDuty/Slack)
module "grafana_provisioning" {
  source = "./modules/grafana_provisioning"

  environment           = var.environment
  prometheus_url        = "http://kube-prometheus-stack-prometheus.${var.kubernetes_namespace}.svc.cluster.local:9090"
  tempo_url             = "http://tempo-query-frontend.${var.kubernetes_namespace}.svc.cluster.local:3200"
  loki_url              = "http://loki.${var.kubernetes_namespace}.svc.cluster.local:3100"
  pagerduty_service_key = var.pagerduty_service_key
  slack_webhook_url     = var.slack_webhook_url

  depends_on = [module.kubernetes_stack]
}
