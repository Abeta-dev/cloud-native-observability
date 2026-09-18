# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
resource "grafana_data_source" "prometheus" {
  type       = "prometheus"
  name       = "Prometheus (${upper(var.environment)})"
  uid        = "prometheus"
  url        = var.prometheus_url
  is_default = true

  json_data_encoded = jsonencode({
    httpMethod        = "POST"
    timeInterval      = "5s"
    manageAlerts      = true
    prometheusType    = "Prometheus"
    prometheusVersion = "2.51.0"
  })
}

resource "grafana_data_source" "tempo" {
  type = "tempo"
  name = "Tempo"
  uid  = "tempo"
  url  = var.tempo_url

  json_data_encoded = jsonencode({
    tracesToLogs = {
      datasourceUid = "loki"
      filterByTrace = true
    }
  })
}

resource "grafana_data_source" "loki" {
  type = "loki"
  name = "Loki"
  uid  = "loki"
  url  = var.loki_url

  json_data_encoded = jsonencode({
    maxLines = 1000
    derivedFields = [
      {
        name          = "TraceID"
        matcherRegex  = "(?:trace_id|traceId)=(\\w+)"
        url           = "$${__data.fields.TraceID}"
        datasourceUid = "tempo"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Dashboard Folders & Dashboards
# -----------------------------------------------------------------------------
resource "grafana_folder" "observability" {
  title = "Core Services & Golden Signals (${upper(var.environment)})"
}

resource "grafana_dashboard" "golden_signals" {
  folder      = grafana_folder.observability.uid
  config_json = file("${path.module}/files/microservice-golden-signals.json")
  overwrite   = true
}

# -----------------------------------------------------------------------------
# Contact Points & Alert Notification Policies
# -----------------------------------------------------------------------------
resource "grafana_contact_point" "slack" {
  count = var.slack_webhook_url != "" ? 1 : 0
  name  = "Slack Observability Alerts"

  slack {
    url                     = var.slack_webhook_url
    recipient               = "#sre-alerts"
    title                   = "{{ template \"slack.default.title\" . }}"
    text                    = "{{ template \"slack.default.text\" . }}"
    disable_resolve_message = false
  }
}

resource "grafana_contact_point" "pagerduty" {
  count = var.pagerduty_service_key != "" ? 1 : 0
  name  = "PagerDuty Critical On-Call"

  pagerduty {
    integration_key         = var.pagerduty_service_key
    disable_resolve_message = false
    severity                = "critical"
  }
}

