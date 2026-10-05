# modules/catalog holds every rule once, for both backends, and has no
# providers. These runs render it for each backend with everything turned on,
# then compare the two.
variables {
  apm = { enabled = true }
  backing_services = {
    mongodb  = { enabled = true }
    mysql    = { enabled = true }
    postgres = { enabled = true }
    rabbitmq = { enabled = true }
    redis    = { enabled = true }
  }
  control_plane = { apiserver = true, etcd = true }
}

run "grafana" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog        = "grafana"
    workload_scope = "zz=\"1\""
  }

  assert {
    condition     = length(output.rules) == 70 && length(output.known_rule_ids) == 70
    error_message = "Expected every rule except the two Datadog-only ones, which Grafana skips."
  }

  assert {
    condition     = keys(output.skipped_rules) == ["agent_not_reporting", "cluster_not_reporting"] && alltrue([for reason in values(output.skipped_rules) : reason != ""])
    error_message = "Only agent_not_reporting and cluster_not_reporting should be skipped on Grafana, each with a reason."
  }
}

run "datadog" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog        = "datadog"
    cluster_scope  = "kube_cluster_name:homelab"
    workload_scope = "zz:1"
  }

  assert {
    condition     = length(output.rules) == 64 && length(output.known_rule_ids) == 64
    error_message = "Expected every rule that has a Datadog block, 62 shared with Grafana plus agent_not_reporting and cluster_not_reporting."
  }

  assert {
    condition     = length(output.skipped_rules) == 8 && alltrue([for reason in values(output.skipped_rules) : reason != ""])
    error_message = "Datadog should skip 8 rules, each with a reason."
  }
}

# A rule with no block and no skip reason for a backend, or without a shared
# field, fails this run. Add the block or `skip = "reason"` to the rule in
# modules/catalog.
run "every_rule_covers_every_backend" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog       = "grafana"
    cluster_scope = "kube_cluster_name:homelab"
  }

  assert {
    condition     = length(output.coverage_gaps.datadog) == 0 && length(output.coverage_gaps.grafana) == 0 && length(output.coverage_gaps.incomplete) == 0
    error_message = "Rules need their shared fields and a block or a skip reason for each backend. Missing a Datadog block: ${join(", ", output.coverage_gaps.datadog)}. Missing a Grafana block: ${join(", ", output.coverage_gaps.grafana)}. Missing a shared field: ${join(", ", output.coverage_gaps.incomplete)}."
  }

  assert {
    condition     = setunion(run.grafana.known_rule_ids, keys(run.grafana.skipped_rules)) == setunion(run.datadog.known_rule_ids, keys(run.datadog.skipped_rules)) && length(setunion(run.grafana.known_rule_ids, keys(run.grafana.skipped_rules))) == 72
    error_message = "Both backends should account for the same 72 rules, as a block or a skip."
  }
}

# The shared fields live once, so they can only differ between backends where a
# backend's block replaces one. Adding an override means adding it here, and
# giving the override a comment in the catalog that says why.
run "backends_differ_only_by_documented_overrides" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog       = "grafana"
    cluster_scope = "kube_cluster_name:homelab"
  }

  assert {
    condition = jsonencode(output.backend_overrides) == jsonencode({
      apiserver_client_certificate_expiring = { datadog = ["operator", "threshold"] }
      deployment_unavailable                = { datadog = ["threshold"] }
      mongodb_down                          = { datadog = ["threshold"] }
      mysql_down                            = { datadog = ["threshold"] }
      node_systemd_service_failed           = { datadog = ["threshold"] }
      postgres_down                         = { datadog = ["threshold"] }
      redis_down                            = { datadog = ["threshold"] }
      scrape_target_down                    = { datadog = ["threshold"] }
      x509_certificate_expiring_critical    = { datadog = ["threshold"] }
      x509_certificate_expiring_warning     = { datadog = ["threshold"] }
    })
    error_message = "A backend block replaces a shared field that isn't in this list: ${jsonencode(output.backend_overrides)}."
  }

  assert {
    condition = alltrue([
      for id in setintersection(keys(run.grafana.rules), keys(run.datadog.rules)) : alltrue([
        for field in ["group", "operator", "severity", "threshold", "title"] :
        run.grafana.rules[id][field] == run.datadog.rules[id][field]
        || contains(try(output.backend_overrides[id].datadog, []), field)
        || contains(try(output.backend_overrides[id].grafana, []), field)
      ])
    ])
    error_message = "A shared field differs between the Grafana and Datadog catalogs without a backend override: ${join(", ", flatten([for id in setintersection(keys(run.grafana.rules), keys(run.datadog.rules)) : [for field in ["group", "operator", "severity", "threshold", "title"] : "${id}.${field}" if run.grafana.rules[id][field] != run.datadog.rules[id][field] && !contains(try(output.backend_overrides[id].datadog, []), field) && !contains(try(output.backend_overrides[id].grafana, []), field)]]))}."
  }

  assert {
    condition     = alltrue([for id, r in run.datadog.rules : r.threshold == run.grafana.rules[id].threshold || contains(try(output.backend_overrides[id].datadog, []), "threshold") if contains(keys(run.grafana.rules), id)])
    error_message = "A Datadog threshold differs from the Grafana one without an override."
  }
}

run "workload_rules_take_the_workload_scope" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog       = "grafana"
    cluster_scope = "kube_cluster_name:homelab"
  }

  assert {
    condition     = alltrue([for id, r in run.grafana.rules : strcontains(r.expr, "zz=\"1\"") == try(r.workload, false)])
    error_message = "A Grafana rule takes the workload selector exactly when it is marked workload."
  }

  assert {
    condition     = alltrue([for id, r in run.datadog.rules : strcontains(try(r.query, ""), "kube_cluster_name:homelab AND zz:1") == try(r.workload, false) if try(r.type, "") != "service check"])
    error_message = "A Datadog rule takes the workload scope exactly when it is marked workload."
  }
}

run "no_placeholder_is_left_in_a_rule" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog       = "grafana"
    cluster_scope = "kube_cluster_name:homelab"
  }

  assert {
    condition     = alltrue([for id, r in run.grafana.rules : !strcontains("${r.expr} ${r.subject} ${r.summary}", "$${")])
    error_message = "Every placeholder in a Grafana rule should be filled in."
  }

  assert {
    condition     = alltrue([for id, r in run.datadog.rules : !strcontains("${r.query} ${r.summary}", "$${")])
    error_message = "Every placeholder in a Datadog rule should be filled in."
  }
}

run "rules_render_per_backend" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog       = "datadog"
    cluster_scope = "kube_cluster_name:homelab"
  }

  assert {
    condition     = run.grafana.rules.pod_crash_looping.expr == "sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{zz=\"1\"}[15m]))" && run.grafana.rules.pod_crash_looping.pending_period == "1m"
    error_message = "The Grafana catalog should render PromQL with the workload selector filled in."
  }

  assert {
    condition     = run.datadog.rules.pod_crash_looping.query == "sum(last_15m):default_zero(diff(max:kubernetes_state.container.restarts{kube_cluster_name:homelab AND zz:1} by {kube_namespace,pod_name,kube_container_name}))" && run.datadog.rules.pod_crash_looping.window == "last_15m"
    error_message = "The Datadog catalog should render the query without its comparison, scoped to the cluster and workload."
  }

  assert {
    condition     = run.datadog.rules.scrape_target_down.threshold == 40 && run.datadog.rules.scrape_target_down.query == "\"kubernetes.kubelet.check\".over(\"kube_cluster_name:homelab\").by(\"host\").last(41).count_by_status()"
    error_message = "A service check's threshold counts failed runs, and its query looks back one run further."
  }

  assert {
    condition     = run.grafana.rules.scrape_target_down.threshold == 1 && run.grafana.rules.scrape_target_down.operator == "lt"
    error_message = "Grafana's scrape_target_down alerts when `up` drops below 1."
  }
}

run "overrides_apply_to_either_backend" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog        = "grafana"
    disabled_rules = ["node_network_errors"]
    overrides = {
      node_disk_full = { pending_period = "30m", severity = "warning", threshold = 90, window = "last_1h" }
      pod_pending    = { paused = true }
    }
  }

  assert {
    condition     = output.rules.node_disk_full.threshold == 90 && output.rules.node_disk_full.severity == "warning" && output.rules.node_disk_full.pending_period == "30m" && !contains(keys(output.rules.node_disk_full), "window")
    error_message = "Grafana overrides change the threshold, severity and pending period, and ignore window."
  }

  assert {
    condition     = output.rules.pod_pending.paused && !output.rules.node_disk_full.paused && !contains(output.rule_ids, "node_network_errors") && contains(output.known_rule_ids, "node_network_errors")
    error_message = "paused applies to the rule, and a disabled rule is left out but still known."
  }
}

run "datadog_overrides_use_window" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog       = "datadog"
    cluster_scope = "kube_cluster_name:homelab"
    overrides = {
      node_disk_full     = { pending_period = "30m", threshold = 90, window = "last_1h" }
      scrape_target_down = { threshold = 20 }
    }
  }

  assert {
    condition     = output.rules.node_disk_full.window == "last_1h" && output.rules.node_disk_full.threshold == 90 && !contains(keys(output.rules.node_disk_full), "pending_period")
    error_message = "Datadog overrides change the window and ignore pending_period."
  }

  assert {
    condition     = strcontains(output.rules.scrape_target_down.query, ".last(21).")
    error_message = "A service check's threshold override should change how many runs it looks back over."
  }
}

run "control_plane_and_groups_gate_rules" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    apm              = {}
    backing_services = {}
    catalog          = "grafana"
    control_plane    = { etcd = true }
  }

  assert {
    condition     = contains(output.rule_ids, "etcd_no_leader") && !contains(output.rule_ids, "apiserver_errors") && !contains(output.rule_ids, "service_error_rate_high") && !contains(output.rule_ids, "postgres_down")
    error_message = "control_plane, apm and backing_services should turn their rules on and leave the rest off."
  }

  assert {
    condition     = length(output.rule_ids) == 46 && length(output.known_rule_ids) == 70
    error_message = "By default, expected the 45 core rules plus etcd_no_leader, out of 70 known."
  }
}

run "unknown_rule_ids_are_rejected" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog        = "grafana"
    disabled_rules = ["not_a_rule"]
  }

  expect_failures = [output.rules]
}

run "datadog_needs_a_cluster_scope" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog = "datadog"
  }

  expect_failures = [var.cluster_scope]
}

run "catalog_must_be_a_known_backend" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    catalog = "prometheus"
  }

  expect_failures = [var.catalog]
}

# The selector variables have two forms: {scope} after a metric name, and
# ,scope inside braces that already hold a matcher. Both drop out when the
# scope is empty.
run "scopes_fill_in_the_selector_forms" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    apm              = { enabled = true, scope = "env=\"prod\"" }
    backing_services = { postgres = { enabled = true }, scope = "namespace=\"db\"" }
    catalog          = "grafana"
    workload_scope   = "namespace=\"a\""
  }

  assert {
    condition     = output.rules.pod_pending.expr == "max by (namespace, pod) (kube_pod_status_phase{phase=\"Pending\",namespace=\"a\"})" && output.rules.job_failed.expr == "max by (namespace, job_name) (kube_job_failed{condition=\"true\",namespace=\"a\"})"
    error_message = "A workload rule should take the workload scope after a matcher."
  }

  assert {
    condition     = output.rules.service_error_rate_high.expr == "100 * sum by (job) (rate(http_server_request_duration_seconds_count{http_response_status_code=~\"5..\",env=\"prod\"}[5m])) / sum by (job) (rate(http_server_request_duration_seconds_count{env=\"prod\"}[5m])) and on (job) sum by (job) (rate(http_server_request_duration_seconds_count{env=\"prod\"}[5m])) >= 0.1"
    error_message = "An APM rule should take apm.scope in every selector, in both forms."
  }

  assert {
    condition     = output.rules.postgres_down.expr == "min by (instance) (pg_up{namespace=\"db\"})"
    error_message = "A backing-service rule should take backing_services.scope."
  }
}

run "empty_scopes_leave_no_selector" {
  command = plan

  module {
    source = "./modules/catalog"
  }

  variables {
    apm              = { enabled = true }
    backing_services = { postgres = { enabled = true } }
    catalog          = "grafana"
  }

  assert {
    condition     = output.rules.pod_pending.expr == "max by (namespace, pod) (kube_pod_status_phase{phase=\"Pending\"})" && output.rules.job_not_completed.expr == "max by (namespace, job_name) (time() - kube_job_status_start_time and on (namespace, job_name) kube_job_status_active > 0)"
    error_message = "With no workload scope, a selector should disappear, with its braces when it was alone."
  }

  assert {
    condition     = output.rules.service_error_rate_high.expr == "100 * sum by (job) (rate(http_server_request_duration_seconds_count{http_response_status_code=~\"5..\"}[5m])) / sum by (job) (rate(http_server_request_duration_seconds_count[5m])) and on (job) sum by (job) (rate(http_server_request_duration_seconds_count[5m])) >= 0.1"
    error_message = "With no apm.scope, an APM rule should have no empty selector."
  }

  assert {
    condition     = output.rules.postgres_down.expr == "min by (instance) (pg_up)"
    error_message = "With no backing_services.scope, a backing-service rule should have no empty selector."
  }
}
