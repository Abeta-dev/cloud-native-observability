variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "trace_retention_days" {
  type        = number
  description = "Days before traces are deleted"
  default     = 30
}

variable "log_retention_days" {
  type        = number
  description = "Days before logs are deleted"
  default     = 30
}
