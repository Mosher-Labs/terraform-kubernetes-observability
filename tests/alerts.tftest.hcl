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
    condition     = length(output.rule_ids) == 45
    error_message = "Expected the 43 workload, node, synthetic and alerting rules plus the two apiserver rules."
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
    condition     = length(output.rule_ids) == 46
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

run "backing_services_are_off_by_default" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
  }

  assert {
    condition     = length([for id, r in output.rules : id if r.group == "backing-services"]) == 0
    error_message = "No backing-service rules should exist until a section is enabled."
  }
}

run "each_backing_service_section_is_separate" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    backing_services = {
      postgres = { connections_percent = 70, enabled = true }
      redis    = { enabled = true }
      selector = "namespace=\"data\""
    }
    cluster_name = "homelab"
  }

  assert {
    condition     = sort([for id, r in output.rules : id if r.group == "backing-services"]) == sort(["postgres_connections_high", "postgres_deadlocks", "postgres_down", "postgres_replication_lag", "redis_down", "redis_memory_high", "redis_rejected_connections"])
    error_message = "Only the Postgres and Redis rules should be created."
  }

  assert {
    condition     = output.rules.postgres_connections_high.threshold == 70
    error_message = "Section thresholds should apply."
  }

  assert {
    condition     = strcontains(output.rules.postgres_down.expr, "pg_up{namespace=\"data\"}") && strcontains(output.rules.redis_memory_high.expr, "redis_memory_max_bytes{namespace=\"data\"}")
    error_message = "The selector should scope every backing-service rule."
  }

  assert {
    condition     = alltrue([for id, r in output.rules : !strcontains(r.expr, "__BSEL__") if r.group == "backing-services"])
    error_message = "No selector placeholder should be left."
  }
}

run "backing_rule_ids_are_known_when_off" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
    overrides    = { rabbitmq_queue_backlog = { threshold = 50 } }
  }

  assert {
    condition     = !contains(output.rule_ids, "rabbitmq_queue_backlog")
    error_message = "Overriding a backing-service rule that's off should be accepted and create nothing."
  }
}

run "heartbeat_rule_is_opt_in" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
  }

  assert {
    condition     = length(grafana_rule_group.heartbeat) == 0
    error_message = "No heartbeat rule unless heartbeat_enabled is set."
  }
}

run "heartbeat_rule_always_fires_and_fails_quiet" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name      = "homelab"
    heartbeat_enabled = true
  }

  assert {
    condition     = one(grafana_rule_group.heartbeat[0].rule).labels.heartbeat == "true"
    error_message = "The heartbeat rule needs the heartbeat label for routing."
  }

  assert {
    condition     = one(grafana_rule_group.heartbeat[0].rule).exec_err_state == "OK" && one(grafana_rule_group.heartbeat[0].rule).no_data_state == "OK"
    error_message = "Datasource errors must stop the heartbeat, not turn it into an error alert."
  }
}

run "custom_rules_join_the_catalog" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
    custom_rules = {
      argocd_app_unhealthy = {
        expr           = "max by (name) (argocd_app_info{health_status!~\"Healthy|Progressing\"})"
        group          = "argocd"
        operator       = "gt"
        pending_period = "15m"
        severity       = "warning"
        subject        = "{{ $labels.name }}"
        summary        = "Argo CD app {{ $labels.name }} is unhealthy."
        threshold      = 0
        title          = "Argo CD app unhealthy"
      }
    }
    overrides = { argocd_app_unhealthy = { severity = "critical" } }
  }

  assert {
    condition     = contains(output.rule_ids, "argocd_app_unhealthy") && output.rules.argocd_app_unhealthy.title == "[homelab] Argo CD app unhealthy"
    error_message = "A custom rule should be created with the cluster title prefix."
  }

  assert {
    condition     = output.rules.argocd_app_unhealthy.severity == "critical" && output.rules.argocd_app_unhealthy.group == "argocd"
    error_message = "Overrides should apply to custom rules, and their group should be kept."
  }

  assert {
    condition     = contains(keys(grafana_rule_group.this), "argocd")
    error_message = "A custom rule's group should become its own rule group."
  }
}

run "custom_rules_can_be_disabled" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
    custom_rules = {
      mine = {
        expr           = "vector(1)"
        group          = "custom"
        operator       = "gt"
        pending_period = "1m"
        severity       = "info"
        subject        = "x"
        summary        = "x"
        threshold      = 0
        title          = "Mine"
      }
    }
    disabled_rules = ["mine"]
  }

  assert {
    condition     = !contains(output.rule_ids, "mine")
    error_message = "disabled_rules should accept custom rule IDs."
  }
}

run "custom_rules_cannot_reuse_catalog_ids" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
    custom_rules = {
      node_disk_full = {
        expr           = "vector(1)"
        group          = "custom"
        operator       = "gt"
        pending_period = "1m"
        severity       = "info"
        subject        = "x"
        summary        = "x"
        threshold      = 0
        title          = "Clash"
      }
    }
  }

  expect_failures = [grafana_folder.this]
}

run "custom_rules_need_a_valid_operator" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name = "homelab"
    custom_rules = {
      bad = {
        expr           = "vector(1)"
        group          = "custom"
        operator       = "eq"
        pending_period = "1m"
        severity       = "info"
        subject        = "x"
        summary        = "x"
        threshold      = 0
        title          = "Bad"
      }
    }
  }

  expect_failures = [var.custom_rules]
}
