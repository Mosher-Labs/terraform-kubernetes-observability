output "monitors" {
  description = "Every datadog_monitor argument, keyed by rule ID. modules/datadog creates one monitor per entry."
  value = {
    for id, r in local.rules : id => {
      draft_status        = r.paused ? "draft" : "published"
      group               = r.group
      message             = trimspace("${local.message_prefix}\n${r.summary}\n\n${join(" ", var.notification_handles)}")
      name                = r.title
      on_missing_data     = r.on_missing_data
      priority            = local.priorities[r.severity]
      query               = r.query
      renotify_interval   = var.renotify_interval_minutes[r.severity]
      require_full_window = r.metric ? r.require_full_window : null
      severity            = r.severity
      tags                = concat(var.tags, ["cluster:${var.cluster_name}", "group:${r.group}", "rule_id:${id}", "severity:${r.severity}"])
      threshold           = r.threshold
      type                = r.type
      window              = r.window
    }
  }

  precondition {
    condition     = length(local.unknown_ids) == 0
    error_message = "Unknown rule IDs in disabled_rules or overrides: ${join(", ", local.unknown_ids)}."
  }
}

output "mapped_rule_ids" {
  description = "Every rule this module can create a monitor for, whether or not it's enabled."
  value       = sort(keys(local.all_rules))
}

output "rule_ids" {
  description = "IDs of the rules that have a monitor, after the apm, backing_services and control_plane flags and disabled_rules are applied."
  value       = sort(keys(local.rules))
}

output "skipped_rules" {
  description = "modules/alerts catalog rules that have no Datadog monitor, with the reason and what to use instead."
  value       = local.skipped_rules
}
