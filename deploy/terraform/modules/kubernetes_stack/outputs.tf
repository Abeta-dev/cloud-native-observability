output "namespace" {
  value       = kubernetes_namespace.monitoring.metadata[0].name
  description = "Kubernetes namespace for monitoring stack"
}

output "prometheus_release_name" {
  value       = helm_release.kube_prometheus_stack.name
  description = "Helm release name for kube-prometheus-stack"
}

output "tempo_release_name" {
  value       = helm_release.tempo.name
  description = "Helm release name for Tempo"
}

output "loki_release_name" {
  value       = helm_release.loki.name
  description = "Helm release name for Loki"
}

output "grafana_admin_password" {
  value       = local.grafana_password
  description = "Initial admin password configured in the grafana-admin-credentials secret"
  sensitive   = true
}

output "alertmanager_endpoint" {
  value       = "http://${helm_release.kube_prometheus_stack.name}-alertmanager.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9093"
  description = "Internal Kubernetes service endpoint for Alertmanager"
}

output "tempo_query_endpoint" {
  value       = "http://tempo-query-frontend.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3200"
  description = "Internal Kubernetes service endpoint for Tempo query frontend"
}

output "tempo_distributor_endpoint" {
  value       = "tempo-distributor.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:4317"
  description = "Internal Kubernetes service endpoint for Tempo OTLP distributor"
}

