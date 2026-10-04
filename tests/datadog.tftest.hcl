# These runs use modules/datadog/catalog, which renders every monitor
# argument without the Datadog provider. Declaring DataDog/datadog in the
# root module would make every caller download it.
mock_provider "grafana" {}

# The Grafana catalog on a cluster with every control-plane rule, for the
# sync check below.
run "grafana_catalog" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    apm = { enabled = true }
    backing_services = {
      mongodb  = { enabled = true }
      mysql    = { enabled = true }
      postgres = { enabled = true }
      rabbitmq = { enabled = true }
      redis    = { enabled = true }
    }
    cluster_name              = "homelab"
    cluster_type              = "generic"
    prometheus_datasource_uid = "prometheus"
  }
}

run "every_catalog_rule_is_mapped_or_skipped" {
  command = plan

  module {
    source = "./modules/datadog/catalog"
  }

  variables {
    cluster_name         = "homelab"
    notification_handles = ["@slack-homelab"]
  }

  assert {
    condition     = length(setsubtract(run.grafana_catalog.rule_ids, concat(output.mapped_rule_ids, keys(output.skipped_rules)))) == 0
    error_message = "Every modules/alerts rule (core, APM and backing services) needs a Datadog monitor or an entry in skipped_rules: ${join(", ", setsubtract(run.grafana_catalog.rule_ids, concat(output.mapped_rule_ids, keys(output.skipped_rules))))}."
  }

  assert {
    condition     = length(setintersection(output.mapped_rule_ids, keys(output.skipped_rules))) == 0
    error_message = "A rule can't be both mapped and skipped."
  }

  assert {
    condition     = length(output.mapped_rule_ids) == 61 && length(output.skipped_rules) == 8
    error_message = "Expected 60 mapped catalog rules plus cluster_not_reporting, and 8 skipped."
  }

  assert {
    condition     = length(output.rule_ids) == 36
    error_message = "By default, expected the 35 core rules without control-plane, APM or backing-service rules, plus cluster_not_reporting."
  }

  assert {
    condition     = !contains(output.rule_ids, "apiserver_errors") && !contains(output.rule_ids, "etcd_no_leader") && !contains(output.rule_ids, "service_error_rate_high") && !contains(output.rule_ids, "postgres_down")
    error_message = "Control-plane, APM and backing-service rules should be off by default."
  }
}

run "monitors_render_queries_thresholds_and_handles" {
  command = plan

  module {
    source = "./modules/datadog/catalog"
  }

  variables {
    cluster_name         = "homelab"
    notification_handles = ["@slack-homelab", "@webhook-oncall"]
    tags                 = ["team:platform"]
  }

  assert {
    condition     = output.monitors["pod_crash_looping"].query == "sum(last_15m):default_zero(diff(max:kubernetes_state.container.restarts{kube_cluster_name:homelab} by {kube_namespace,pod_name,kube_container_name})) > 5"
    error_message = "pod_crash_looping should sum restart deltas over 15 minutes, scoped to the cluster, compared with > 5."
  }

  assert {
    condition     = output.monitors["pod_crash_looping"].threshold == 5
    error_message = "The critical threshold must match the threshold in the query."
  }

  assert {
    condition     = output.monitors["cluster_not_reporting"].query == "max(last_10m):sum:kubernetes_state.node.count{kube_cluster_name:homelab} < 1"
    error_message = "cluster_not_reporting should alert when the node count drops below 1."
  }

  assert {
    condition     = output.monitors["cluster_not_reporting"].on_missing_data == "show_and_notify_no_data"
    error_message = "cluster_not_reporting must notify when data stops, since that is the outage it watches for."
  }

  assert {
    condition     = alltrue([for m in output.monitors : m.on_missing_data != "resolve"])
    error_message = "No monitor may resolve on missing data; it hides real outages."
  }

  assert {
    condition     = alltrue([for m in output.monitors : endswith(m.message, "@slack-homelab @webhook-oncall")])
    error_message = "Every monitor should notify every handle."
  }

  assert {
    condition     = alltrue([for m in output.monitors : startswith(m.message, "{{#is_alert}}🔴 FIRING{{/is_alert}}")]) && strcontains(output.monitors["pod_pending"].message, "{{#is_recovery}}✅ RESOLVED{{/is_recovery}}")
    error_message = "Every message should start with the FIRING/RESOLVED line, matching the Grafana backend's titles."
  }

  assert {
    condition     = output.monitors["scrape_target_down"].type == "service check" && output.monitors["scrape_target_down"].query == "\"datadog.agent.check_status\".over(\"kube_cluster_name:homelab\").by(\"check\",\"host\").last(41).count_by_status()" && output.monitors["scrape_target_down"].threshold == 40
    error_message = "scrape_target_down should be a service check on the Agent's check status, alerting after 40 failed runs."
  }

  assert {
    condition     = output.monitors["scrape_target_down"].on_missing_data == null && output.monitors["scrape_target_down"].require_full_window == null
    error_message = "Service checks don't take on_missing_data or require_full_window."
  }

  assert {
    condition     = output.monitors["node_not_ready"].priority == 1 && output.monitors["node_memory_high"].priority == 3
    error_message = "Critical rules should be priority 1 and warning rules priority 3."
  }

  assert {
    condition     = output.monitors["node_not_ready"].renotify_interval == 60 && output.monitors["node_memory_high"].renotify_interval == 240
    error_message = "Renotify intervals should follow severity: 60 minutes for critical, 240 for warning."
  }

  assert {
    condition     = toset(output.monitors["pod_pending"].tags) == toset(["team:platform", "cluster:homelab", "group:pods", "rule_id:pod_pending", "severity:warning"])
    error_message = "Monitors should carry the extra tags plus cluster, group, rule_id and severity."
  }

  assert {
    condition     = output.monitors["pod_pending"].name == "[homelab] Pod stuck pending"
    error_message = "Monitor names should start with the cluster name, as Grafana rule titles do."
  }

  assert {
    condition     = alltrue([for m in output.monitors : m.draft_status == "published"]) && output.monitors["pod_pending"].type == "query alert"
    error_message = "Monitors should be published by default."
  }
}

run "overrides_scope_and_disabled_rules" {
  command = plan

  module {
    source = "./modules/datadog/catalog"
  }

  variables {
    cluster_name   = "prod"
    cluster_tag    = "cluster"
    disabled_rules = ["node_network_errors"]
    overrides = {
      node_not_ready    = { paused = true }
      pod_crash_looping = { severity = "warning", threshold = 10, window = "last_30m" }
    }
    workload_scope = "NOT kube_namespace:kube-system"
  }

  assert {
    condition     = output.monitors["pod_crash_looping"].query == "sum(last_30m):default_zero(diff(max:kubernetes_state.container.restarts{cluster:prod AND NOT kube_namespace:kube-system} by {kube_namespace,pod_name,kube_container_name})) > 10"
    error_message = "Overrides should change the window and threshold, and workload rules should add workload_scope to the cluster scope."
  }

  assert {
    condition     = output.monitors["pod_crash_looping"].threshold == 10 && output.monitors["pod_crash_looping"].priority == 3
    error_message = "The overridden threshold and severity should reach the monitor."
  }

  assert {
    condition     = strcontains(output.monitors["node_disk_full"].query, "{cluster:prod}")
    error_message = "Node rules should be scoped to the cluster only, without workload_scope."
  }

  assert {
    condition     = output.monitors["node_not_ready"].draft_status == "draft"
    error_message = "A paused rule should be a draft monitor, which sends no notifications."
  }

  assert {
    condition     = !contains(output.rule_ids, "node_network_errors")
    error_message = "Disabled rules should not create monitors."
  }
}

run "unknown_rule_ids_are_rejected" {
  command = plan

  module {
    source = "./modules/datadog/catalog"
  }

  variables {
    cluster_name = "homelab"
    overrides    = { not_a_rule = { threshold = 1 } }
  }

  expect_failures = [output.monitors]
}

run "handles_must_start_with_at" {
  command = plan

  module {
    source = "./modules/datadog/catalog"
  }

  variables {
    cluster_name         = "homelab"
    notification_handles = ["slack-homelab"]
  }

  expect_failures = [var.notification_handles]
}

run "apm_backing_and_control_plane_rules" {
  command = plan

  module {
    source = "./modules/datadog/catalog"
  }

  variables {
    apm = { enabled = true, scope = "env:prod", span_name = "servlet.request" }
    backing_services = {
      postgres = { enabled = true, connections_percent = 70 }
      redis    = { enabled = true }
      scope    = "kube_namespace:db"
    }
    cluster_name  = "homelab"
    control_plane = { apiserver = true, etcd = true }
  }

  assert {
    condition     = length(output.rule_ids) == 36 + 3 + 6 + 4 + 3
    error_message = "Expected the default rules plus the 3 control-plane rules, the 6 APM rules, 4 Postgres and 3 Redis rules."
  }

  assert {
    condition     = output.monitors["service_error_rate_high"].query == "avg(last_5m):100 * sum:trace.servlet.request.errors{env:prod} by {service}.as_rate() / cutoff_min(sum:trace.servlet.request.hits{env:prod} by {service}.as_rate(), 0.1) > 5"
    error_message = "APM error rate should read the configured span's trace metrics in the APM scope, floored at min_requests_per_second."
  }

  assert {
    condition     = output.monitors["service_traffic_drop"].threshold == 25 && endswith(output.monitors["service_traffic_drop"].query, "< 25")
    error_message = "Traffic drop should alert below 100 - traffic_drop_percent."
  }

  assert {
    condition     = output.monitors["postgres_connections_high"].query == "min(last_10m):100 * max:postgresql.percent_usage_connections{kube_cluster_name:homelab AND kube_namespace:db} by {host} > 70"
    error_message = "Backing-service rules should add the backing scope to the cluster tag and use the section's threshold."
  }

  assert {
    condition     = output.monitors["postgres_down"].type == "service check" && output.monitors["postgres_down"].query == "\"postgres.can_connect\".over(\"kube_cluster_name:homelab\").by(\"host\").last(9).count_by_status()"
    error_message = "postgres_down should be a service check on postgres.can_connect, alerting after 8 failed runs (2 minutes)."
  }

  assert {
    condition     = output.monitors["apiserver_errors"].query == "avg(last_10m):100 * sum:kube_apiserver.apiserver_request_total.count{code:5* AND kube_cluster_name:homelab}.as_rate() / sum:kube_apiserver.apiserver_request_total.count{kube_cluster_name:homelab}.as_rate() > 5"
    error_message = "apiserver_errors should use the kube_apiserver_metrics check's request counter."
  }

  assert {
    condition     = output.monitors["etcd_no_leader"].query == "max(last_1m):min:etcd.server.has_leader{kube_cluster_name:homelab} by {host} < 1"
    error_message = "etcd_no_leader should alert when etcd.server.has_leader drops below 1."
  }

  assert {
    condition     = !contains(output.rule_ids, "mysql_down") && !contains(output.rule_ids, "rabbitmq_alarm")
    error_message = "Backing-service sections that aren't enabled should create no rules."
  }
}

run "cluster_health_rules" {
  command = plan

  module {
    source = "./modules/datadog/catalog"
  }

  variables {
    cluster_name   = "homelab"
    workload_scope = "NOT kube_namespace:kube-system"
  }

  assert {
    condition     = output.monitors["pod_not_ready"].query == "min(last_15m):default_zero(max:kubernetes_state.pod.ready{condition:false AND kube_cluster_name:homelab AND NOT kube_namespace:kube-system} by {kube_namespace,pod_name}) * default_zero(max:kubernetes_state.pod.status_phase{pod_phase:running AND kube_cluster_name:homelab AND NOT kube_namespace:kube-system} by {kube_namespace,pod_name}) > 0"
    error_message = "pod_not_ready should multiply not-ready by running, scoped like other workload rules."
  }

  assert {
    condition     = output.monitors["node_clock_skew"].query == "min(last_10m):abs(max:ntp.offset{kube_cluster_name:homelab} by {host}) > 0.05"
    error_message = "node_clock_skew should read the NTP check's offset."
  }

  assert {
    condition     = output.monitors["node_systemd_service_failed"].type == "service check" && strcontains(output.monitors["node_systemd_service_failed"].query, ".last(21).")
    error_message = "node_systemd_service_failed should be a service check alerting after 20 failed runs (5 minutes)."
  }

  assert {
    condition     = strcontains(output.monitors["persistent_volume_errors"].query, "{phase IN (failed,pending) AND kube_cluster_name:homelab}")
    error_message = "PersistentVolumes are cluster-wide, so workload_scope shouldn't apply."
  }

  assert {
    condition     = !contains(output.rule_ids, "apiserver_client_certificate_expiring")
    error_message = "apiserver_client_certificate_expiring needs control_plane.apiserver."
  }
}

run "service_check_threshold_override" {
  command = plan

  module {
    source = "./modules/datadog/catalog"
  }

  variables {
    cluster_name = "homelab"
    overrides    = { scrape_target_down = { threshold = 20 } }
  }

  assert {
    condition     = strcontains(output.monitors["scrape_target_down"].query, ".last(21).") && output.monitors["scrape_target_down"].threshold == 20
    error_message = "A service check's threshold override should change how many failed runs it takes."
  }
}
