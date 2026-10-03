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
    condition     = one([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p if p.type == "alertlist"]).options.alertInstanceLabelFilter == "{cluster=\"Home Lab\", heartbeat!=\"true\"}"
    error_message = "The alert list should show only this cluster's alerts."
  }
}

run "services_row_only_with_apm" {
  command = plan

  module {
    source = "./modules/dashboards"
  }

  assert {
    condition     = !contains([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p.title], "Services")
    error_message = "No Services row unless APM is enabled."
  }
}

run "services_row_uses_the_apm_metric" {
  command = plan

  module {
    source = "./modules/dashboards"
  }

  variables {
    apm = {
      enabled       = true
      metric        = "grafana_http_request_duration_seconds"
      route_label   = "handler"
      selector      = "namespace=\"monitoring\""
      service_label = "job"
      status_label  = "status_code"
    }
  }

  assert {
    condition     = contains([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p.title], "Services")
    error_message = "APM should add the Services row."
  }

  assert {
    condition     = strcontains(one([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p if p.title == "5xx error rate"]).targets[0].expr, "grafana_http_request_duration_seconds_count{status_code=~\"5..\",namespace=\"monitoring\"}")
    error_message = "The error-rate panel should use the APM metric, status label and selector."
  }

  assert {
    condition     = strcontains(one([for p in jsondecode(grafana_dashboard.overview.config_json).panels : p if p.title == "Slowest routes, p90"]).targets[0].expr, "sum by (job, handler, le)")
    error_message = "The slowest-routes table should group by service and route."
  }
}
