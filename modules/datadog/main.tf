# The monitors module renders every monitor argument without the Datadog
# provider, so the root module's tests can check it. It reads the rules from
# modules/catalog.
module "monitors" {
  source = "./monitors"

  apm                                = var.apm
  backing_services                   = var.backing_services
  cluster_name                       = var.cluster_name
  cluster_tag                        = var.cluster_tag
  control_plane                      = var.control_plane
  disabled_rules                     = var.disabled_rules
  metric_notification_handles        = local.metric_handles
  notification_handles               = local.handles
  overrides                          = var.overrides
  renotify_interval_minutes          = var.renotify_interval_minutes
  service_check_notification_handles = local.service_check_handles
  tags                               = var.tags
  workload_scope                     = var.workload_scope
}

resource "datadog_monitor" "this" {
  for_each = module.monitors.monitors

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
}
