variable "environment" {
  type        = string
  description = "Target deployment environment"
}

variable "prometheus_url" {
  type        = string
  description = "Prometheus service endpoint URL"
  default     = "http://prometheus:9090"
}

variable "tempo_url" {
  type        = string
  description = "Tempo OpenTelemetry traces endpoint URL"
  default     = "http://tempo:3200"
}

variable "loki_url" {
  type        = string
  description = "Loki logs endpoint URL"
  default     = "http://loki:3100"
}

variable "pagerduty_service_key" {
  type        = string
  description = "PagerDuty Integration Key for critical incident routing"
  sensitive   = true
  default     = ""
}

variable "slack_webhook_url" {
  type        = string
  description = "Slack Webhook URL for warning alerts"
  sensitive   = true
  default     = ""
}
