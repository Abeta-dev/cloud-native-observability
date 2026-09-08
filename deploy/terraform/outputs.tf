output "tempo_s3_bucket" {
  value       = var.enable_cloud_storage == "true" ? module.storage[0].tempo_bucket_name : "N/A"
  description = "S3 bucket storing OpenTelemetry traces for Tempo"
}

output "loki_s3_bucket" {
  value       = var.enable_cloud_storage == "true" ? module.storage[0].loki_bucket_name : "N/A"
  description = "S3 bucket storing logs for Loki"
}

output "kubernetes_namespace" {
  value       = module.kubernetes_stack.namespace
  description = "Kubernetes namespace housing the observability workloads"
}

output "grafana_folder_uid" {
  value       = module.grafana_provisioning.folder_uid
  description = "Grafana dashboard folder UID"
}

output "grafana_dashboard_url" {
  value       = module.grafana_provisioning.dashboard_url
  description = "Direct URL to provisioned Golden Signals dashboard in Grafana"
}

output "grafana_admin_password" {
  value       = module.kubernetes_stack.grafana_admin_password
  description = "Initial admin password configured in the grafana-admin-credentials secret"
  sensitive   = true
}
