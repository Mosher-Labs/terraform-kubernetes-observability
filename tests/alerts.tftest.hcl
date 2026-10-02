mock_provider "grafana" {}

variables {
  prometheus_datasource_uid = "prometheus"
}

run "k3s_has_apiserver_but_not_etcd" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
    cluster_type = "k3s"
  }

  assert {
    condition     = contains(output.rule_ids, "apiserver_errors")
    error_message = "k3s exposes API server metrics, so apiserver_errors should be included."
  }

  assert {
    condition     = !contains(output.rule_ids, "etcd_no_leader")
    error_message = "k3s defaults to SQLite, so etcd_no_leader should be left out."
  }

  assert {
    condition     = length(output.rule_ids) == 29
    error_message = "Expected the 28 workload, node and synthetic rules plus apiserver_errors."
  }
}

run "managed_clusters_skip_control_plane" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "prod"
    cluster_type = "eks"
  }

  assert {
    condition     = !contains(output.rule_ids, "apiserver_errors") && !contains(output.rule_ids, "etcd_no_leader")
    error_message = "EKS hides control-plane metrics, so neither control-plane rule should be created."
  }
}

run "generic_includes_all_rules" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "lab"
  }

  assert {
    condition     = length(output.rule_ids) == 30
    error_message = "A generic cluster should get every catalog rule."
  }
}

run "control_plane_override" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name  = "homelab"
    cluster_type  = "k3s"
    control_plane = { etcd = true }
  }

  assert {
    condition     = contains(output.rule_ids, "etcd_no_leader")
    error_message = "control_plane.etcd = true should add etcd_no_leader on k3s."
  }
}

run "disabled_rules_and_overrides" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name   = "homelab"
    disabled_rules = ["node_network_errors"]
    overrides = {
      node_disk_full = { pending_period = "30m", severity = "warning", threshold = 90 }
    }
  }

  assert {
    condition     = !contains(output.rule_ids, "node_network_errors")
    error_message = "A disabled rule should not be created."
  }

  assert {
    condition     = output.rules.node_disk_full.threshold == 90 && output.rules.node_disk_full.severity == "warning" && output.rules.node_disk_full.pending_period == "30m"
    error_message = "Overrides should replace the threshold, severity and pending period."
  }

  assert {
    condition     = output.rules.pod_pending.threshold == 0 && output.rules.pod_pending.severity == "warning"
    error_message = "Rules without overrides should keep the catalog defaults."
  }
}

run "unknown_rule_id_is_rejected" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name   = "homelab"
    disabled_rules = ["not_a_rule"]
  }

  expect_failures = [grafana_folder.this]
}

run "workload_selector_scopes_workload_rules_only" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name      = "homelab"
    workload_selector = "namespace!~\"kube-system\""
  }

  assert {
    condition     = strcontains(output.rules.pod_pending.expr, "{phase=\"Pending\",namespace!~\"kube-system\"}")
    error_message = "The selector should be added inside an existing matcher list."
  }

  assert {
    condition     = strcontains(output.rules.pod_crash_looping.expr, "kube_pod_container_status_restarts_total{namespace!~\"kube-system\"}")
    error_message = "The selector should fill an empty matcher list."
  }

  assert {
    condition     = !strcontains(output.rules.node_not_ready.expr, "kube-system")
    error_message = "Node rules should not take the workload selector."
  }
}

run "no_selector_leaves_no_placeholder" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
  }

  assert {
    condition     = alltrue([for r in values(output.rules) : !strcontains(r.expr, "__SEL__") && !strcontains(r.expr, "{}")])
    error_message = "With no selector, every placeholder should be removed without leaving empty braces."
  }
}

run "bad_cluster_type_is_rejected" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
    cluster_type = "minikube"
  }

  expect_failures = [var.cluster_type]
}

run "every_rule_has_a_subject" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
  }

  assert {
    condition     = alltrue([for r in values(output.rules) : r.subject != ""])
    error_message = "Every rule needs a subject for notification titles."
  }
}

run "apm_rules_are_off_by_default" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
  }

  assert {
    condition     = length([for id, r in output.rules : id if r.group == "apm"]) == 0
    error_message = "APM rules should only exist when apm.enabled is set."
  }
}

run "apm_rules_use_the_configured_metric_and_labels" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    apm = {
      enabled                 = true
      latency_p90_seconds     = 2
      metric                  = "grafana_http_request_duration_seconds"
      min_requests_per_second = 0.5
      route_label             = "handler"
      selector                = "namespace=\"monitoring\""
      service_label           = "job"
      status_label            = "status_code"
    }
    cluster_name = "homelab"
  }

  assert {
    condition     = length([for id, r in output.rules : id if r.group == "apm"]) == 6
    error_message = "Enabling APM should add its 6 rules."
  }

  assert {
    condition     = strcontains(output.rules.service_error_rate_high.expr, "grafana_http_request_duration_seconds_count{status_code=~\"5..\",namespace=\"monitoring\"}")
    error_message = "The metric, status label and selector should be substituted."
  }

  assert {
    condition     = strcontains(output.rules.endpoint_error_rate_high.expr, "sum by (job, handler)") && strcontains(output.rules.endpoint_error_rate_high.expr, ">= 0.5")
    error_message = "The service and route labels and the traffic floor should be substituted."
  }

  assert {
    condition     = output.rules.service_latency_p90_high.threshold == 2 && output.rules.service_traffic_drop.threshold == 25
    error_message = "Thresholds should come from the apm settings."
  }

  assert {
    condition     = alltrue([for id, r in output.rules : !strcontains(r.expr, "__") && !strcontains(r.subject, "__") if r.group == "apm"])
    error_message = "No placeholder should be left in an APM rule."
  }
}

run "apm_rule_ids_are_known_even_when_off" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name   = "homelab"
    disabled_rules = ["service_traffic_drop"]
  }

  assert {
    condition     = !contains(output.rule_ids, "service_traffic_drop")
    error_message = "Disabling an APM rule while APM is off should be accepted."
  }
}
