output "alert_folder_uid" {
  description = "UID of the Grafana folder that holds the alert rules, or null when alerts are off."
  value       = try(module.alerts[0].folder_uid, null)
}

output "alert_rule_ids" {
  description = "IDs of the alert rules that were created."
  value       = try(module.alerts[0].rule_ids, [])
}

output "contact_point_name" {
  description = "Name of the contact point, or null when notifications are off."
  value       = try(module.notifications[0].contact_point_name, null)
}

output "dashboard_url" {
  description = "URL of the overview dashboard, or null when dashboards are off."
  value       = try(module.dashboards[0].dashboard_url, null)
}

output "enabled_channels" {
  description = "The notification channels that are turned on."
  value       = try(module.notifications[0].enabled_channels, [])
}
