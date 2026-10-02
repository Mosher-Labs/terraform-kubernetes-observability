resource "grafana_folder" "this" {
  title = coalesce(var.folder_title, "Kubernetes dashboards (${var.cluster_name})")
}

resource "grafana_dashboard" "overview" {
  config_json = jsonencode(local.dashboard)
  folder      = grafana_folder.this.uid
  message     = "Managed by terraform-kubernetes-observability"
  overwrite   = true
}
