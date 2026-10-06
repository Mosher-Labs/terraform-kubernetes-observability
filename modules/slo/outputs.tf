output "burn_rates" {
  description = "The burn-rate threshold of each tier for each SLO, for the SLO document."
  value       = local.burn_rate
}

output "custom_rules" {
  description = "Burn-rate alert rules in the shape `modules/alerts` takes as `custom_rules`, keyed `<slo>_burn_<tier>`."
  value       = local.rules
}
