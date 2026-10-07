resource "grafana_folder" "this" {
  title = coalesce(var.folder_title, "Kubernetes dashboards (${var.cluster_name})")
}

resource "grafana_dashboard" "overview" {
  config_json = jsonencode(local.dashboard)
  folder      = grafana_folder.this.uid
  message     = "Managed by terraform-kubernetes-observability"
  overwrite   = true
}

# One dashboard with every SLO, when there are any.
resource "grafana_dashboard" "slos" {
  count = length(var.slos) > 0 ? 1 : 0

  config_json = jsonencode(local.slo_dashboard)
  folder      = grafana_folder.this.uid
  message     = "Managed by terraform-kubernetes-observability"
  overwrite   = true
}
