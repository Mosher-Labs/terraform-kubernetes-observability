resource "grafana_folder" "this" {
  title = coalesce(var.folder_title, "Kubernetes alerts (${var.cluster_name})")

  lifecycle {
    precondition {
      condition     = length(local.colliding_ids) == 0
      error_message = "custom_rules reuses catalog rule IDs: ${join(", ", local.colliding_ids)}. Pick other IDs, or use overrides to change a catalog rule."
    }

    precondition {
      condition     = length(local.unknown_ids) == 0
      error_message = "Unknown rule IDs in disabled_rules or overrides: ${join(", ", local.unknown_ids)}."
    }
  }
}

resource "grafana_rule_group" "this" {
  for_each = toset(local.groups)

  folder_uid       = grafana_folder.this.uid
  interval_seconds = var.evaluation_interval_seconds
  name             = each.key

  dynamic "rule" {
    # Sorted by ID so the plan stays stable.
    for_each = { for id in sort(keys(local.rules)) : id => local.rules[id] if local.rules[id].group == each.key }
    content {
      annotations = {
        # What the alert is about, such as "api in prod", for short titles.
        subject = rule.value.subject
        summary = rule.value.summary
      }
      condition      = "B"
      exec_err_state = "Error"
      for            = rule.value.pending_period
      is_paused      = rule.value.paused
      labels = merge(var.labels, {
        cluster  = var.cluster_name
        rule_id  = rule.key
        severity = rule.value.severity
      })
      name = rule.value.title
      # A series that disappears (a deleted pod, say) is not a problem.
      no_data_state = "OK"

      # Query A, then threshold B on it: B depends on A, so keep this order.
      data {
        datasource_uid = var.prometheus_datasource_uid
        model = jsonencode({
          expr    = rule.value.expr
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
              params = [rule.value.threshold]
              type   = rule.value.operator
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
}
