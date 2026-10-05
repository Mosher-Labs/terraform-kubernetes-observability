# The catalog holds every rule once for both backends. This module takes the
# Datadog rules from it and creates one monitor for each.
module "catalog" {
  source = "../catalog"

  apm              = var.apm
  backing_services = var.backing_services
  catalog          = "datadog"
  cluster_scope    = local.cluster_scope
  control_plane    = var.control_plane
  disabled_rules   = var.disabled_rules
  overrides        = var.overrides
  # The monitors below check the IDs, so the error comes from them.
  validate_rule_ids = false
  workload_scope    = var.workload_scope
}

resource "datadog_monitor" "this" {
  for_each = local.monitors

  draft_status        = each.value.draft_status
  include_tags        = true
  message             = each.value.message
  name                = each.value.name
  on_missing_data     = each.value.on_missing_data
  priority            = each.value.priority
  query               = each.value.query
  renotify_interval   = each.value.renotify_interval
  require_full_window = each.value.require_full_window
  tags                = each.value.tags
  type                = each.value.type

  # Metric monitors: matches the threshold at the end of the query. Service
  # checks: consecutive failed runs to alert, and one success to recover.
  monitor_thresholds {
    critical = each.value.threshold
    ok       = each.value.type == "service check" ? 1 : null
  }

  lifecycle {
    precondition {
      condition     = length(local.unknown_ids) == 0
      error_message = "Unknown rule IDs in disabled_rules or overrides: ${join(", ", local.unknown_ids)}."
    }
  }
}
