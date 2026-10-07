output "dashboard_uid" {
  description = "UID of the overview dashboard."
  value       = grafana_dashboard.overview.uid
}

output "dashboard_url" {
  description = "URL of the overview dashboard."
  value       = grafana_dashboard.overview.url
}

output "folder_uid" {
  description = "UID of the folder that holds the dashboard."
  value       = grafana_folder.this.uid
}

output "slo_dashboard_uid" {
  description = "UID of the SLO dashboard, or null when there are no SLOs."
  value       = one(grafana_dashboard.slos[*].uid)
}

output "slo_dashboard_url" {
  description = "URL of the SLO dashboard, or null when there are no SLOs."
  value       = one(grafana_dashboard.slos[*].url)
}
