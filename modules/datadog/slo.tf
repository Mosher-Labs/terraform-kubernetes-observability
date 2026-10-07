# SLOs from modules/slo: one metric SLO each, and a burn-rate monitor for each
# alert tier. Datadog evaluates both windows itself, as the Grafana rules do.
resource "datadog_service_level_objective" "this" {
  for_each = var.slos

  description = "${each.value.name}. Created by terraform-kubernetes-observability."
  name        = "[${var.cluster_name}] ${each.value.name}"
  tags        = concat(var.tags, ["cluster:${var.cluster_name}", "group:${each.value.group}", "slo:${each.key}"])
  type        = "metric"

  query {
    denominator = each.value.denominator
    numerator   = each.value.numerator
  }

  thresholds {
    target    = each.value.target
    timeframe = each.value.timeframe
  }
}

resource "datadog_monitor" "slo" {
  for_each = local.slo_monitors

  draft_status      = each.value.draft_status
  include_tags      = true
  message           = each.value.message
  name              = each.value.name
  priority          = local.priorities[each.value.severity]
  query             = each.value.query
  renotify_interval = var.renotify_interval_minutes[each.value.severity]
  tags              = each.value.tags
  type              = "slo alert"

  monitor_thresholds {
    critical = each.value.threshold
  }

  lifecycle {
    precondition {
      condition     = length(local.unknown_ids) == 0
      error_message = "Unknown rule IDs in disabled_rules or overrides: ${join(", ", local.unknown_ids)}."
    }
  }
}
