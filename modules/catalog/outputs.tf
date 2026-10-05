output "backend_overrides" {
  description = "The shared fields a backend's block replaces, as rule ID => backend => field names. Rules without overrides are left out."
  value       = local.backend_overrides
}

output "coverage_gaps" {
  description = "Rules that lack a shared field, or a block or skip reason for a backend, as backend => rule IDs. Empty lists mean the catalog is complete. `incomplete` lists rules that miss a shared field."
  value = {
    datadog    = local.coverage_gaps.datadog
    grafana    = local.coverage_gaps.grafana
    incomplete = local.incomplete_rules
  }
}

output "known_rule_ids" {
  description = "Every rule ID this backend can render, whether or not it is enabled."
  value       = sort(keys(local.backend_rules))

  precondition {
    condition     = length(local.uncovered_ids) == 0
    error_message = "Every rule needs its shared fields and, for each backend, a block or a skip reason. Gaps: ${join(", ", local.uncovered_ids)}."
  }
}

output "rule_ids" {
  description = "IDs of the rules turned on, after the apm, backing_services and control_plane flags and disabled_rules are applied."
  value       = sort(keys(local.rules))
}

output "rules" {
  description = "The rules turned on, keyed by rule ID. Each has its shared fields (group, title, severity, operator, threshold, and requires and workload where set), `paused`, and the backend's fields: grafana gives expr, pending_period, subject and summary; datadog gives query (the monitor query without its comparison, or the full query for a service check), summary, window and, where set, type, require_full_window, on_missing_data and default_zero. Overrides are applied and every placeholder is filled in."
  value       = local.rules

  precondition {
    condition     = length(local.uncovered_ids) == 0
    error_message = "Every rule needs its shared fields and, for each backend, a block or a skip reason. Gaps: ${join(", ", local.uncovered_ids)}."
  }

  precondition {
    condition     = !var.validate_rule_ids || length(local.unknown_ids) == 0
    error_message = "Unknown rule IDs in disabled_rules or overrides: ${join(", ", local.unknown_ids)}."
  }
}

output "skipped_rules" {
  description = "Rules this backend can't express, with the reason and what to use instead."
  value       = local.skipped_rules
}
