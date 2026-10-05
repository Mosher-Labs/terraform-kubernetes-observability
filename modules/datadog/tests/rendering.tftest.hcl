# Run from modules/datadog: terraform init -backend=false && terraform test.
# These runs check the monitor arguments the module builds from the catalog's
# Datadog rules: queries with their comparison, thresholds, messages, tags and
# priorities. The catalog's own tests are in the root tests/catalog.tftest.hcl.
mock_provider "datadog" {}

run "catalog_rules_are_mapped_or_skipped" {
  command = plan

  variables {
    cluster_name         = "homelab"
    notification_handles = ["@slack-homelab"]
  }

  assert {
    condition     = length(module.catalog.known_rule_ids) == 64 && length(output.skipped_rules) == 8
    error_message = "Expected 62 mapped catalog rules plus agent_not_reporting and cluster_not_reporting, and 8 skipped."
  }

  assert {
    condition     = length(setintersection(module.catalog.known_rule_ids, keys(output.skipped_rules))) == 0
    error_message = "A rule can't be both mapped and skipped."
  }

  assert {
    condition     = length(output.rule_ids) == 39
    error_message = "By default, expected the 37 core rules without control-plane, APM or backing-service rules, plus agent_not_reporting and cluster_not_reporting."
  }

  assert {
    condition     = !contains(output.rule_ids, "apiserver_errors") && !contains(output.rule_ids, "etcd_no_leader") && !contains(output.rule_ids, "service_error_rate_high") && !contains(output.rule_ids, "postgres_down")
    error_message = "Control-plane, APM and backing-service rules should be off by default."
  }
}

run "monitors_render_queries_thresholds_and_handles" {
  command = plan

  variables {
    cluster_name         = "homelab"
    notification_handles = ["@slack-homelab", "@webhook-oncall"]
    tags                 = ["team:platform"]
  }

  assert {
    condition     = local.monitors["pod_crash_looping"].query == "sum(last_15m):default_zero(diff(max:kubernetes_state.container.restarts{kube_cluster_name:homelab} by {kube_namespace,pod_name,kube_container_name})) > 5"
    error_message = "pod_crash_looping should sum restart deltas over 15 minutes, scoped to the cluster, compared with > 5."
  }

  assert {
    condition     = local.monitors["pod_crash_looping"].threshold == 5
    error_message = "The critical threshold must match the threshold in the query."
  }

  assert {
    condition     = local.monitors["cluster_not_reporting"].query == "max(last_10m):sum:kubernetes_state.node.count{kube_cluster_name:homelab} < 1"
    error_message = "cluster_not_reporting should alert when the node count drops below 1."
  }

  assert {
    condition     = local.monitors["cluster_not_reporting"].on_missing_data == "show_and_notify_no_data"
    error_message = "cluster_not_reporting must notify when data stops, since that is the outage it watches for."
  }

  assert {
    condition     = alltrue([for m in local.monitors : m.on_missing_data != "resolve"])
    error_message = "No monitor may resolve on missing data; it hides real outages."
  }

  assert {
    condition     = alltrue([for m in local.monitors : endswith(m.message, "@slack-homelab @webhook-oncall")])
    error_message = "Every monitor should notify every handle."
  }

  assert {
    condition     = alltrue([for m in local.monitors : startswith(m.message, "{{#is_alert}}🔴 FIRING{{/is_alert}}")]) && strcontains(local.monitors["pod_pending"].message, "{{#is_recovery}}✅ RESOLVED{{/is_recovery}}")
    error_message = "Every message should start with the FIRING/RESOLVED line, matching the Grafana backend's titles."
  }

  assert {
    condition     = local.monitors["scrape_target_down"].type == "service check" && local.monitors["scrape_target_down"].query == "\"kubernetes.kubelet.check\".over(\"kube_cluster_name:homelab\").by(\"host\").last(41).count_by_status()" && local.monitors["scrape_target_down"].threshold == 40
    error_message = "scrape_target_down should be a service check on the kubelet's health, alerting after 40 failed runs."
  }

  assert {
    condition     = local.monitors["x509_certificate_expiring_warning"].query == "min(last_1h):min:x509.cert_expires_in_seconds{kube_cluster_name:homelab} by {filepath,subject_cn} < 2592000" && local.monitors["x509_certificate_expiring_warning"].threshold == 2592000
    error_message = "x509_certificate_expiring_warning should alert below 30 days, in seconds, on the OpenMetrics check's metric, with no default_zero() (a gap must not fire)."
  }

  assert {
    condition     = local.monitors["x509_certificate_expiring_critical"].query == "min(last_1h):min:x509.cert_expires_in_seconds{kube_cluster_name:homelab} by {filepath,subject_cn} < 604800" && local.monitors["x509_certificate_expiring_critical"].threshold == 604800 && local.monitors["x509_certificate_expiring_critical"].priority == 1
    error_message = "x509_certificate_expiring_critical should alert below 7 days, in seconds, at priority 1."
  }

  assert {
    condition     = local.monitors["scrape_target_down"].on_missing_data == null && local.monitors["scrape_target_down"].require_full_window == null
    error_message = "Service checks don't take on_missing_data or require_full_window."
  }

  assert {
    condition     = local.monitors["node_not_ready"].priority == 1 && local.monitors["node_memory_high"].priority == 3
    error_message = "Critical rules should be priority 1 and warning rules priority 3."
  }

  assert {
    condition     = local.monitors["node_not_ready"].renotify_interval == 60 && local.monitors["node_memory_high"].renotify_interval == 240
    error_message = "Renotify intervals should follow severity: 60 minutes for critical, 240 for warning."
  }

  assert {
    condition     = toset(local.monitors["pod_pending"].tags) == toset(["team:platform", "cluster:homelab", "group:pods", "rule_id:pod_pending", "severity:warning"])
    error_message = "Monitors should carry the extra tags plus cluster, group, rule_id and severity."
  }

  assert {
    condition     = local.monitors["pod_pending"].name == "[homelab] Pod stuck pending"
    error_message = "Monitor names should start with the cluster name, as Grafana rule titles do."
  }

  assert {
    condition     = alltrue([for m in local.monitors : m.draft_status == "published"]) && local.monitors["pod_pending"].type == "query alert"
    error_message = "Monitors should be published by default."
  }
}

run "overrides_scope_and_disabled_rules" {
  command = plan

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
    condition     = local.monitors["pod_crash_looping"].query == "sum(last_30m):default_zero(diff(max:kubernetes_state.container.restarts{cluster:prod AND NOT kube_namespace:kube-system} by {kube_namespace,pod_name,kube_container_name})) > 10"
    error_message = "Overrides should change the window and threshold, and workload rules should add workload_scope to the cluster scope."
  }

  assert {
    condition     = local.monitors["pod_crash_looping"].threshold == 10 && local.monitors["pod_crash_looping"].priority == 3
    error_message = "The overridden threshold and severity should reach the monitor."
  }

  assert {
    condition     = strcontains(local.monitors["node_disk_full"].query, "{cluster:prod}")
    error_message = "Node rules should be scoped to the cluster only, without workload_scope."
  }

  assert {
    condition     = local.monitors["node_not_ready"].draft_status == "draft"
    error_message = "A paused rule should be a draft monitor, which sends no notifications."
  }

  assert {
    condition     = !contains(output.rule_ids, "node_network_errors")
    error_message = "Disabled rules should not create monitors."
  }
}

run "unknown_rule_ids_are_rejected" {
  command = plan

  variables {
    cluster_name = "homelab"
    overrides    = { not_a_rule = { threshold = 1 } }
  }

  expect_failures = [datadog_monitor.this]
}

run "handles_must_start_with_at" {
  command = plan

  variables {
    cluster_name         = "homelab"
    notification_handles = ["slack-homelab"]
  }

  expect_failures = [var.notification_handles]
}

run "apm_backing_and_control_plane_rules" {
  command = plan

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
    condition     = length(output.rule_ids) == 39 + 3 + 6 + 4 + 3
    error_message = "Expected the default rules plus the 3 control-plane rules, the 6 APM rules, 4 Postgres and 3 Redis rules."
  }

  assert {
    condition     = local.monitors["service_error_rate_high"].query == "avg(last_5m):default_zero(100 * sum:trace.servlet.request.errors{env:prod} by {service}.as_rate() / cutoff_min(sum:trace.servlet.request.hits{env:prod} by {service}.as_rate(), 0.1)) > 5"
    error_message = "APM error rate should read the configured span's trace metrics in the APM scope, floored at min_requests_per_second."
  }

  assert {
    condition     = local.monitors["service_traffic_drop"].threshold == 25 && endswith(local.monitors["service_traffic_drop"].query, "< 25")
    error_message = "Traffic drop should alert below 100 - traffic_drop_percent."
  }

  assert {
    condition     = local.monitors["postgres_connections_high"].query == "min(last_10m):default_zero(100 * max:postgresql.percent_usage_connections{kube_cluster_name:homelab AND kube_namespace:db} by {host}) > 70"
    error_message = "Backing-service rules should add the backing scope to the cluster tag and use the section's threshold."
  }

  assert {
    condition     = local.monitors["postgres_down"].type == "service check" && local.monitors["postgres_down"].query == "\"postgres.can_connect\".over(\"kube_cluster_name:homelab\").by(\"host\").last(9).count_by_status()"
    error_message = "postgres_down should be a service check on postgres.can_connect, alerting after 8 failed runs (2 minutes)."
  }

  assert {
    condition     = local.monitors["apiserver_errors"].query == "avg(last_10m):default_zero(100 * sum:kube_apiserver.apiserver_request_total.count{code:5* AND kube_cluster_name:homelab}.as_rate() / sum:kube_apiserver.apiserver_request_total.count{kube_cluster_name:homelab}.as_rate()) > 5"
    error_message = "apiserver_errors should use the kube_apiserver_metrics check's request counter."
  }

  assert {
    condition     = local.monitors["etcd_no_leader"].query == "max(last_1m):min:etcd.server.has_leader{kube_cluster_name:homelab} by {host} < 1"
    error_message = "etcd_no_leader should alert when etcd.server.has_leader drops below 1."
  }

  assert {
    condition     = !contains(output.rule_ids, "mysql_down") && !contains(output.rule_ids, "rabbitmq_alarm")
    error_message = "Backing-service sections that aren't enabled should create no rules."
  }
}

run "cluster_health_rules" {
  command = plan

  variables {
    cluster_name   = "homelab"
    workload_scope = "NOT kube_namespace:kube-system"
  }

  assert {
    condition     = local.monitors["pod_not_ready"].query == "min(last_15m):default_zero(max:kubernetes_state.pod.ready{condition:false AND kube_cluster_name:homelab AND NOT kube_namespace:kube-system} by {kube_namespace,pod_name}) * default_zero(max:kubernetes_state.pod.status_phase{pod_phase:running AND kube_cluster_name:homelab AND NOT kube_namespace:kube-system} by {kube_namespace,pod_name}) > 0"
    error_message = "pod_not_ready should multiply not-ready by running, scoped like other workload rules."
  }

  assert {
    condition     = local.monitors["node_clock_skew"].query == "min(last_30m):default_zero(abs(max:ntp.offset{kube_cluster_name:homelab} by {host})) > 0.05"
    error_message = "node_clock_skew should read the NTP check's offset."
  }

  assert {
    condition     = local.monitors["node_systemd_service_failed"].type == "service check" && strcontains(local.monitors["node_systemd_service_failed"].query, ".last(21).")
    error_message = "node_systemd_service_failed should be a service check alerting after 20 failed runs (5 minutes)."
  }

  assert {
    condition     = strcontains(local.monitors["persistent_volume_errors"].query, "{phase IN (failed,pending) AND kube_cluster_name:homelab}")
    error_message = "PersistentVolumes are cluster-wide, so workload_scope shouldn't apply."
  }

  assert {
    condition     = !contains(output.rule_ids, "apiserver_client_certificate_expiring")
    error_message = "apiserver_client_certificate_expiring needs control_plane.apiserver."
  }
}

run "service_check_threshold_override" {
  command = plan

  variables {
    cluster_name = "homelab"
    overrides    = { scrape_target_down = { threshold = 20 } }
  }

  assert {
    condition     = strcontains(local.monitors["scrape_target_down"].query, ".last(21).") && local.monitors["scrape_target_down"].threshold == 20
    error_message = "A service check's threshold override should change how many failed runs it takes."
  }
}

run "deleted_objects_resolve" {
  command = plan

  variables {
    cluster_name = "homelab"
  }

  assert {
    condition     = local.monitors["deployment_under_replicated"].query == "min(last_10m):default_zero(max:kubernetes_state.deployment.replicas_desired{kube_cluster_name:homelab} by {kube_namespace,kube_deployment} - max:kubernetes_state.deployment.replicas_available{kube_cluster_name:homelab} by {kube_namespace,kube_deployment}) > 0"
    error_message = "Rules that alert above a threshold should fill gaps with 0, so a deleted Deployment's alert resolves."
  }

  assert {
    condition     = !strcontains(local.monitors["cluster_not_reporting"].query, "default_zero")
    error_message = "Rules that alert below a threshold must keep their gaps, or a 0 would fire them."
  }
}

run "agent_not_reporting_notifies_on_no_data" {
  command = plan

  variables {
    cluster_name = "homelab"
  }

  assert {
    condition     = local.monitors["agent_not_reporting"].type == "service check" && local.monitors["agent_not_reporting"].query == "\"datadog.agent.up\".over(\"kube_cluster_name:homelab\").by(\"host\").last(2).count_by_status()" && local.monitors["agent_not_reporting"].threshold == 1
    error_message = "agent_not_reporting should be a service check on datadog.agent.up per host, alerting after 1 failed run."
  }

  assert {
    condition     = local.monitors["agent_not_reporting"].notify_no_data == true && local.monitors["agent_not_reporting"].no_data_timeframe == 10
    error_message = "agent_not_reporting must notify on no data after 10 minutes: a dead Agent sends no status, and Datadog requires it for this host-level check."
  }

  assert {
    condition     = datadog_monitor.this["agent_not_reporting"].notify_no_data == true && datadog_monitor.this["agent_not_reporting"].no_data_timeframe == 10 && datadog_monitor.this["agent_not_reporting"].type == "service check"
    error_message = "The no-data options should reach the monitor resource."
  }

  assert {
    condition     = alltrue([for id, m in local.monitors : m.notify_no_data == null && m.no_data_timeframe == null if id != "agent_not_reporting"])
    error_message = "Other rules should leave notify_no_data and no_data_timeframe unset."
  }
}
