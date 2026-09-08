terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 3.0.0"
    }
  }
}

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

# -----------------------------------------------------------------------------
# SRE Golden Signals Alert Rule Group
# -----------------------------------------------------------------------------
resource "grafana_rule_group" "golden_signal_rules" {
  name             = "Microservice Golden Signal Alerts"
  folder_uid       = grafana_folder.observability.uid
  interval_seconds = 60

  rule {
    name           = "HighErrorRateP1"
    condition      = "B"
    for            = "2m"
    no_data_state  = "NoData"
    exec_err_state = "Error"

    annotations = {
      summary     = "Microservice HTTP error rate exceeded 5%"
      description = "Microservice error rate is currently {{ $values.B.Value }}% which exceeds the 5% SLO threshold."
      runbook_url = "https://github.com/umesh0492/cloud-native-observability/blob/main/docs/RUNBOOKS.md#high-error-rate"
    }

    labels = {
      severity = "critical"
      tier     = "tier-1"
      team     = "platform-sre"
    }

    data {
      ref_id     = "A"
      query_type = ""
      relative_time_range {
        from = 300
        to   = 0
      }
      datasource_uid = grafana_data_source.prometheus.uid
      model = jsonencode({
        expr         = "(sum(rate(http_requests_total{status=~\"[45]..\"}[1m])) / sum(rate(http_requests_total[1m]))) * 100"
        instant      = true
        intervalMs   = 1000
        maxDataPoints = 43200
        refId        = "A"
      })
    }

    data {
      ref_id     = "B"
      query_type = ""
      relative_time_range {
        from = 300
        to   = 0
      }
      datasource_uid = "-100" # Grafana Expression engine
      model = jsonencode({
        conditions = [
          {
            evaluator = {
              params = [5]
              type   = "gt"
            }
            operator = {
              type = "and"
            }
            query = {
              params = ["A"]
            }
            reducer = {
              params = []
              type   = "last"
            }
            type = "query"
          }
        ]
        datasource = {
          name = "Expression"
          type = "__expr__"
          uid  = "-100"
        }
        expression = "A"
        refId      = "B"
        type       = "threshold"
      })
    }
  }

  rule {
    name           = "CircuitBreakerTrippedP2"
    condition      = "B"
    for            = "1m"
    no_data_state  = "KeepLast"
    exec_err_state = "Error"

    annotations = {
      summary     = "Upstream dependency Circuit Breaker tripped to OPEN state"
      description = "Circuit breaker has opened to protect downstream services from cascading failure."
      runbook_url = "https://github.com/umesh0492/cloud-native-observability/blob/main/docs/RUNBOOKS.md#circuit-breaker-open"
    }

    labels = {
      severity = "warning"
      tier     = "tier-2"
      team     = "platform-sre"
    }

    data {
      ref_id     = "A"
      query_type = ""
      relative_time_range {
        from = 300
        to   = 0
      }
      datasource_uid = grafana_data_source.prometheus.uid
      model = jsonencode({
        expr         = "app_circuit_breaker_state"
        instant      = true
        intervalMs   = 1000
        maxDataPoints = 43200
        refId        = "A"
      })
    }

    data {
      ref_id     = "B"
      query_type = ""
      relative_time_range {
        from = 300
        to   = 0
      }
      datasource_uid = "-100"
      model = jsonencode({
        conditions = [
          {
            evaluator = {
              params = [1]
              type   = "gt"
            }
            operator = {
              type = "and"
            }
            query = {
              params = ["A"]
            }
            reducer = {
              params = []
              type   = "last"
            }
            type = "query"
          }
        ]
        datasource = {
          name = "Expression"
          type = "__expr__"
          uid  = "-100"
        }
        expression = "A"
        refId      = "B"
        type       = "threshold"
      })
    }
  }
}
