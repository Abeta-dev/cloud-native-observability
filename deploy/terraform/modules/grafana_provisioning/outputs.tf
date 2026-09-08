output "folder_uid" {
  value       = grafana_folder.observability.uid
  description = "UID of the provisioned Grafana dashboard folder"
}

output "dashboard_uid" {
  value       = grafana_dashboard.golden_signals.uid
  description = "UID of the Golden Signals dashboard"
}

output "dashboard_url" {
  value       = grafana_dashboard.golden_signals.url
  description = "Direct URL to the provisioned Golden Signals dashboard"
}

output "alert_rule_group_id" {
  value       = grafana_rule_group.golden_signal_rules.id
  description = "ID of the provisioned alert rule group"
}
