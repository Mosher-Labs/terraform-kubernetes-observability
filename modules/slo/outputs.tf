output "burn_rates" {
  description = "The burn-rate threshold of each tier for each SLO, for the SLO document."
  value       = local.burn_rate
}

output "custom_rules" {
  description = "Burn-rate alert rules for the SLOs with a `grafana` block, in the shape `modules/alerts` takes as `custom_rules`, keyed `<slo>_burn_<tier>`."
  value       = local.rules
}

output "datadog_slos" {
  description = "The SLOs with a `datadog` block, in the shape `modules/datadog` takes as `slos`."
  value       = local.datadog_slos
}
