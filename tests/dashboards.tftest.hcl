mock_provider "grafana" {}

variables {
  cluster_name              = "Home Lab"
  prometheus_datasource_uid = "prometheus"
}

run "overview_without_logs" {
  command = plan

  module {
    source = "./modules/dashboards"
  }

  assert {
    condition     = jsondecode(grafana_dashboard.overview.config_json).uid == "k8s-overview-home-lab"
    error_message = "The UID should be derived from the cluster name, lowercased and with unsafe characters replaced."
  }

  assert {
    condition     = !contains([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p.title], "Logs")
    error_message = "Without a Loki datasource there should be no logs row."
  }

  assert {
    condition     = alltrue([for p in jsondecode(grafana_dashboard.overview.config_json).panels : try(p.datasource.uid, "prometheus") == "prometheus"])
    error_message = "Every panel should query the given Prometheus datasource."
  }

  assert {
    condition     = length(distinct([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p.id])) == length(jsondecode(grafana_dashboard.overview.config_json).panels)
    error_message = "Panel IDs must be unique."
  }
}

run "logs_row_with_loki" {
  command = plan

  module {
    source = "./modules/dashboards"
  }

  variables {
    loki_datasource_uid = "loki"
  }

  assert {
    condition     = contains([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p.title], "Errors in logs")
    error_message = "A Loki datasource should add the logs panel."
  }

  assert {
    condition     = one([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p if p.type == "logs"]).targets[0].datasource.uid == "loki"
    error_message = "The logs panel should query the Loki datasource."
  }
}

run "alert_list_filters_on_cluster" {
  command = plan

  module {
    source = "./modules/dashboards"
  }

  assert {
    condition     = one([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p if p.type == "alertlist"]).options.alertInstanceLabelFilter == "{cluster=\"Home Lab\"}"
    error_message = "The alert list should show only this cluster's alerts."
  }
}
