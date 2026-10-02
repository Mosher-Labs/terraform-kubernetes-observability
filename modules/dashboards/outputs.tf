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
