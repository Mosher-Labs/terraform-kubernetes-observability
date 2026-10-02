locals {
  managed_control_plane = contains(["eks", "aks", "gke"], var.cluster_type)

  # k3s defaults to SQLite (kine), so it has an API server but no etcd.
  capabilities = {
    apiserver = coalesce(var.control_plane.apiserver, !local.managed_control_plane)
    etcd      = coalesce(var.control_plane.etcd, contains(["openshift", "generic"], var.cluster_type))
  }

  unknown_ids = setsubtract(setunion(var.disabled_rules, keys(var.overrides)), keys(local.catalog))

  rules = {
    for id, r in local.catalog : id => {
      group     = r.group
      title     = "[${var.cluster_name}] ${r.title}"
      summary   = r.summary
      operator  = r.operator
      threshold = coalesce(try(var.overrides[id].threshold, null), r.threshold)
      for       = coalesce(try(var.overrides[id].for, null), r.for)
      severity  = coalesce(try(var.overrides[id].severity, null), r.severity)
      paused    = coalesce(try(var.overrides[id].paused, null), false)
      expr = replace(
        replace(r.expr, ",__SEL__}", var.workload_selector == "" ? "}" : ",${var.workload_selector}}"),
        "{__SEL__}", var.workload_selector == "" ? "" : "{${var.workload_selector}}",
      )
    }
    if !contains(var.disabled_rules, id) && (try(r.requires, null) == null ? true : local.capabilities[r.requires])
  }

  groups = distinct([for r in values(local.rules) : r.group])
}

resource "grafana_folder" "this" {
  title = coalesce(var.folder_title, "Kubernetes alerts (${var.cluster_name})")

  lifecycle {
    precondition {
      condition     = length(local.unknown_ids) == 0
      error_message = "Unknown rule IDs in disabled_rules or overrides: ${join(", ", local.unknown_ids)}."
    }
  }
}

resource "grafana_rule_group" "this" {
  for_each = toset(local.groups)

  name             = each.key
  folder_uid       = grafana_folder.this.uid
  interval_seconds = var.evaluation_interval_seconds

  dynamic "rule" {
    # Sorted by ID so the plan stays stable.
    for_each = { for id in sort(keys(local.rules)) : id => local.rules[id] if local.rules[id].group == each.key }
    content {
      name      = rule.value.title
      for       = rule.value.for
      condition = "B"
      is_paused = rule.value.paused

      # The queries already filter to bad series, so no data means healthy.
      no_data_state  = "OK"
      exec_err_state = "Error"

      labels = merge(var.labels, {
        cluster  = var.cluster_name
        severity = rule.value.severity
        rule_id  = rule.key
      })

      annotations = {
        summary = rule.value.summary
      }

      data {
        ref_id         = "A"
        datasource_uid = var.prometheus_datasource_uid

        relative_time_range {
          from = 600
          to   = 0
        }

        model = jsonencode({
          refId   = "A"
          expr    = rule.value.expr
          instant = true
        })
      }

      data {
        ref_id         = "B"
        datasource_uid = "__expr__"

        relative_time_range {
          from = 0
          to   = 0
        }

        model = jsonencode({
          refId      = "B"
          type       = "threshold"
          expression = "A"
          conditions = [{
            evaluator = {
              type   = rule.value.operator
              params = [rule.value.threshold]
            }
          }]
        })
      }
    }
  }
}
