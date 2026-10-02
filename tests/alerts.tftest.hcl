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
    condition     = length(output.rule_ids) == 25
    error_message = "Expected the 24 workload and node rules plus apiserver_errors."
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
    condition     = length(output.rule_ids) == 26
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
