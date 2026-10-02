output "contact_point_name" {
  description = "Name of the contact point, for routing alerts to it from your own notification policy."
  value       = grafana_contact_point.this.name
}

output "enabled_channels" {
  description = "The notification channels that are turned on."
  value = compact([
    local.email_enabled ? "email" : "",
    local.slack_enabled ? "slack" : "",
    local.teams_enabled ? "teams" : "",
    local.webex_enabled ? "webex" : "",
  ])
}

output "contact_point_title" {
  description = "The title template the contact point uses."
  value       = var.title_template
}
