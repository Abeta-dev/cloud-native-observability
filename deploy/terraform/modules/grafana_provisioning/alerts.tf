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
      summary     = "Microservice HTTP 5xx error rate exceeded 5%"
      description = "Microservice HTTP 5xx error rate is currently {{ $values.B.Value }}% which exceeds the 5% SLO threshold over 5m."
      runbook_url = "https://github.com/umesh0492/cloud-native-observability/blob/main/docs/RUNBOOKS.md#higherrorrate"
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
        expr          = "(sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m]))) * 100"
        instant       = true
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "A"
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
        expr          = "app_circuit_breaker_state"
        instant       = true
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "A"
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
