# A rule that fires for as long as Grafana can query Prometheus. The
# notifications module routes it, by its heartbeat label, to an outside
# heartbeat service. When the pings stop, because Grafana, Prometheus or the
# whole cluster is down, that service raises the alarm. Errors and missing
# data count as OK, so a broken datasource stops the pings too.
resource "grafana_rule_group" "heartbeat" {
  count = var.heartbeat_enabled ? 1 : 0

  folder_uid       = grafana_folder.this.uid
  interval_seconds = var.evaluation_interval_seconds
  name             = "heartbeat"

  rule {
    annotations = {
      subject = "Grafana and Prometheus"
      summary = "Grafana can evaluate rules against Prometheus. This alert always fires; it isn't a problem."
    }
    condition      = "B"
    exec_err_state = "OK"
    for            = "0s"
    labels = merge(var.labels, {
      cluster   = var.cluster_name
      heartbeat = "true"
      rule_id   = "heartbeat"
      severity  = "none"
    })
    name          = "[${var.cluster_name}] Heartbeat"
    no_data_state = "OK"

    data {
      datasource_uid = var.prometheus_datasource_uid
      model = jsonencode({
        expr    = "vector(1)"
        instant = true
        refId   = "A"
      })
      ref_id = "A"

      relative_time_range {
        from = 600
        to   = 0
      }
    }

    data {
      datasource_uid = "__expr__"
      model = jsonencode({
        conditions = [{
          evaluator = {
            params = [0]
            type   = "gt"
          }
        }]
        expression = "A"
        refId      = "B"
        type       = "threshold"
      })
      ref_id = "B"

      relative_time_range {
        from = 0
        to   = 0
      }
    }
  }
}
