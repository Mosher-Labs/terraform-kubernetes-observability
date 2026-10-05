output "monitor_ids" {
  description = "Datadog monitor IDs, keyed by rule ID."
  value       = { for id, m in datadog_monitor.this : id => m.id }
}

output "monitors" {
  description = "The monitors as created: name, query, threshold, window, severity and group, keyed by rule ID."
  value = {
    for id, m in local.monitors : id => {
      group     = m.group
      name      = m.name
      query     = m.query
      severity  = m.severity
      threshold = m.threshold
      window    = m.window
    }
  }
}

output "rule_ids" {
  description = "IDs of the monitors that were created, after disabled_rules is applied."
  value       = sort(keys(local.monitors))
}

output "skipped_rules" {
  description = "Catalog rules that have no Datadog monitor, with the reason and what to use instead."
  value       = module.catalog.skipped_rules
}
