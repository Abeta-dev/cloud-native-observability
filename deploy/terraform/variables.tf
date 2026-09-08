variable "environment" {
  type        = string
  description = "Target deployment environment (e.g., dev, staging, prod)"
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for observability storage and infrastructure"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix applied to all provisioned observability resources"
  default     = "cloud-native-obs"
}

variable "enable_cloud_storage" {
  type        = string
  description = "Whether to provision cloud S3 buckets for long-term trace and log chunk retention (true/false)"
  default     = "true"
}

variable "trace_retention_days" {
  type        = number
  description = "Retention period in days for distributed traces in Tempo S3 storage"
  default     = 30

  validation {
    condition     = var.trace_retention_days >= 1 && var.trace_retention_days <= 365
    error_message = "Trace retention must be between 1 and 365 days."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Retention period in days for application and system logs in Loki S3 storage"
  default     = 30

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 730
    error_message = "Log retention must be between 1 and 730 days."
  }
}

variable "kubernetes_namespace" {
  type        = string
  description = "Kubernetes namespace where the monitoring stack is deployed"
  default     = "monitoring"
}

variable "grafana_url" {
  type        = string
  description = "Base URL of the Grafana instance for Observability as Code provisioning"
  default     = "http://localhost:3000"
}

variable "grafana_auth" {
  type        = string
  description = "Grafana API Service Account Token or admin:password for authentication"
  sensitive   = true
  default     = "admin:admin"
}

variable "pagerduty_service_key" {
  type        = string
  description = "PagerDuty Integration Key for routing P1/P2 Golden Signal alerts"
  sensitive   = true
  default     = ""
}

variable "slack_webhook_url" {
  type        = string
  description = "Slack incoming webhook URL for observability notifications"
  sensitive   = true
  default     = ""
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

