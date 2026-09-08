variable "namespace" {
  type        = string
  description = "Kubernetes namespace for monitoring"
  default     = "monitoring"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "tempo_s3_bucket" {
  type        = string
  description = "S3 bucket name for Tempo trace storage"
  default     = ""
}

variable "loki_s3_bucket" {
  type        = string
  description = "S3 bucket name for Loki log storage"
  default     = ""
}

variable "aws_region" {
  type        = string
  description = "AWS region for storage access"
  default     = "us-east-1"
}

variable "grafana_admin_password" {
  type        = string
  description = "Admin password for Grafana (set via TF_VAR_grafana_admin_password or secret manager)"
  sensitive   = true
  default     = ""
}

variable "grafana_admin_secret_name" {
  type        = string
  description = "Existing Kubernetes secret name containing Grafana admin credentials"
  default     = "grafana-admin-credentials"
}

variable "alertmanager_slack_webhook_url" {
  type        = string
  description = "Slack webhook URL for Alertmanager notifications (optional)"
  sensitive   = true
  default     = ""
}

variable "alertmanager_pagerduty_routing_key" {
  type        = string
  description = "PagerDuty routing key for Alertmanager critical notifications (optional)"
  sensitive   = true
  default     = ""
}

variable "trace_retention_days" {
  type        = number
  description = "Retention period in days for Tempo distributed traces"
  default     = 30
}

variable "alertmanager_retention" {
  type        = string
  description = "Retention period for Alertmanager notifications"
  default     = "120h"
}


