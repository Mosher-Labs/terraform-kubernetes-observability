# terraform-kubernetes-observability

A Terraform module that sets up Kubernetes alerting in Grafana. It creates a
curated catalog of alert rules for any kind of cluster, and sends alerts to
Slack, email, Webex or Microsoft Teams in any combination.

The alerts are Grafana-managed alert rules, so they work with any
Prometheus-compatible datasource: a self-hosted Prometheus, Amazon or Azure
managed Prometheus, or Grafana Cloud.

## Features

- **An alert catalog** for pods, workloads, resource usage, nodes and the
  control plane. Every threshold, pending period and severity can be overridden,
  and any rule can be turned off.
- **Cluster-type aware.** EKS, AKS and GKE don't expose API server or etcd
  metrics, so those rules are only created for self-managed clusters.
- **An overview dashboard** with cluster health, resources, workloads,
  synthetic checks, the cluster's firing alerts and, with Loki, error logs.
- **Notifications** to Slack, email, Webex and Teams. Each channel is optional
  and independent.
- **Service-level (APM) alerts**, opt in: latency, error rate per service and
  per route, traffic drops, and errors right after a deploy, from any
  request-duration histogram.
- **Backing-service alerts**, opt in per technology: Postgres, MySQL, Redis,
  RabbitMQ and MongoDB.
- **Synthetic checks:** probe a list of URLs, and alert when one fails, gets
  slow, or its TLS certificate is about to expire.
- **Opt-in installs** with `modules/stack`, one flag each: kube-prometheus-stack,
  Loki, Grafana Alloy (pod logs to Loki) and the blackbox exporter (synthetic
  checks). The pieces are wired together: Grafana gets a Loki datasource, Alloy
  ships to Loki, and Prometheus scrapes the probes.
- **Submodules you can use on their own:** `modules/alerts`,
  `modules/dashboards`, `modules/notifications` and `modules/stack`.

## Usage

```hcl
provider "grafana" {
  url  = "https://grafana.example.com"
  auth = var.grafana_token
}

module "observability" {
  source = "github.com/Mosher-Labs/terraform-kubernetes-observability?ref=<commit-sha>"  # vX.Y.Z

  alerts = {
    overrides = {
      node_disk_full = { threshold = 90 }
    }
    workload_selector = "namespace!~\"kube-system\""
  }
  cluster_name = "homelab"
  cluster_type = "k3s"
  notifications = {
    email = { addresses = ["oncall@example.com"] }
  }
  prometheus_datasource_uid = "prometheus"
  slack                     = { url = var.slack_webhook_url }
}
```

See [examples/k3s](examples/k3s) for a complete configuration.

### Requirements

- Grafana 10 or later with unified alerting, and a service account token that
  can manage folders, alert rules, contact points and notification policies.
- A Prometheus-compatible datasource with the metrics from kube-state-metrics,
  node-exporter, cAdvisor (through the kubelet) and, for control-plane rules,
  the API server and etcd. kube-prometheus-stack provides all of them.
- Email needs SMTP configured in Grafana.

### Dashboard

The root module also creates an overview dashboard; see
[modules/dashboards](modules/dashboards) for its panels. Pass
`dashboards.loki_datasource_uid` to add an error-logs panel, or set
`dashboards.enabled = false` to skip it. The `dashboard_url` output links to it.

### Notification policy

Grafana has one notification policy tree per organization. By default the
module manages that tree: everything goes to this module's contact point, and
critical alerts repeat more often than warnings. If something else already
manages your policies, set `notifications.manage_notification_policy = false`
and route on the `cluster` and `severity` labels yourself.

### Channels

[docs/notifications.md](docs/notifications.md) walks through setting up each
channel: Slack (webhook or bot), Microsoft Teams (Workflows), Webex (incoming
webhook or bot) and email.

### Message titles

Slack and Teams titles and email subjects start with 🔴 FIRING or ✅ RESOLVED,
then the alert name and what it is about, for example
`🔴 FIRING (2): [homelab] Pod crash looping – api in prod, worker in prod`. The
"what" comes from each rule's `subject` annotation.
Grafana posts a resolve as a new message, not as a reply to the original, so
the title is what pairs them up. Change it with `notifications.title_template`,
or set a channel's own `title` or `subject`.

Grafana posts to Slack as "Grafana" unless you set `slack.username`, for
example to your Slack app's name. With a bot token, that needs the
`chat:write.customize` scope.

## Installing the stack

The root module only manages Grafana content, so it works with a monitoring
stack you already run. For a cluster with nothing installed, `modules/stack`
installs the pieces with Helm, each behind its own flag:

```hcl
module "stack" {
  source = "github.com/Mosher-Labs/terraform-kubernetes-observability//modules/stack?ref=<commit-sha>"  # vX.Y.Z

  alloy = { enabled = true }
  blackbox_exporter = {
    enabled = true
    targets = [
      { name = "homepage", url = "https://example.com" },
      { name = "api", url = "https://api.example.com/healthz" },
    ]
  }
  cluster_name          = "lab"
  kube_prometheus_stack = { enabled = true }
  loki                  = { enabled = true }
}
```

Every component pins its chart version, which you can override, and takes
extra Helm values files that apply after the module's. Loki defaults to a single
binary with filesystem storage, which suits small clusters. For larger ones,
switch its deployment mode and storage through `loki.values`.

Pass `module.stack.prometheus_datasource_uid` to the root module. Both can live
in one root as long as Terraform can reach the new Grafana; see
[examples/stack](examples/stack).

### Synthetic checks

Each `blackbox_exporter.targets` entry is probed every `interval` (default
60s) with the blackbox exporter's `module` (default `http_2xx`). The
synthetics alerts fire when a check fails for 2 minutes, takes over 5 seconds,
or its TLS certificate expires within 14 days (warning) or 3 days (critical).
The probes run inside the cluster, so they can't tell you the cluster itself is
down. Pair them with a check from outside for that.

## Service-level (APM) alerts

Turn these on with `alerts.apm.enabled = true`. They need request metrics from
each service, as a Prometheus histogram: an OpenTelemetry SDK, a Prometheus
client library, a service mesh or an ingress controller all provide one. The
defaults match OpenTelemetry's HTTP conventions exported to Prometheus
(`http_server_request_duration_seconds`, with `http_route` and
`http_response_status_code` labels). For other instrumentation, set the metric
and label names:

```hcl
alerts = {
  apm = {
    enabled       = true
    metric        = "nginx_ingress_controller_request_duration_seconds"
    route_label   = "path"
    service_label = "service"
    status_label  = "status"
  }
}
```

| ID | Alert | Fires when | Severity |
| --- | --- | --- | --- |
| `service_latency_p90_high` | Service p90 latency high | p90 > `latency_p90_seconds` (1s) for 10m | warning |
| `service_latency_avg_high` | Service average latency high | average > `latency_avg_seconds` (0.5s) for 10m | warning |
| `service_error_rate_high` | Service error rate high | 5xx > `error_rate_percent` (5%) for 5m | critical |
| `endpoint_error_rate_high` | Endpoint error rate high | 5xx on one route > `error_rate_percent` for 5m | warning |
| `service_traffic_drop` | Service traffic dropped | traffic falls by `traffic_drop_percent` (75%) against its last hour, for 10m | warning |
| `service_errors_after_deploy` | Errors after a deploy | 5xx > `deploy_error_rate_percent` (1%) within 30 minutes of a rollout in the same namespace | warning |

Rules only judge a service, or a route, with at least
`min_requests_per_second` (0.1), so a slow endpoint with two requests can't
raise a 100% error rate. Re-baseline the thresholds against real traffic. A
service whose metrics vanish entirely has no data and stays quiet; synthetic
checks cover that case. `service_errors_after_deploy` needs a `namespace`
label on the request metrics, which Prometheus adds when it scrapes pods.

## Backing-service alerts

Turn on a section per technology in `alerts.backing_services`. Each reads the
metrics of that technology's standard Prometheus exporter, so the exporter has
to be running and scraped:

| Section | Exporter | Rules |
| --- | --- | --- |
| `postgres` | [postgres_exporter](https://github.com/prometheus-community/postgres_exporter) | down, connections > 80% of `max_connections`, replication lag > 30s, deadlocks |
| `mysql` | [mysqld_exporter](https://github.com/prometheus/mysqld_exporter) | down, connections > 80% of `max_connections`, replication lag > 30s |
| `redis` | [redis_exporter](https://github.com/oliver006/redis_exporter) | down, memory > 90% of `maxmemory`, rejected connections |
| `rabbitmq` | RabbitMQ's built-in `rabbitmq_prometheus` plugin | resource alarm, > 1000 messages ready, > 1000 unacknowledged |
| `mongodb` | [mongodb_exporter](https://github.com/percona/mongodb_exporter) | down, connections > 80%, replica set lag > 30s |

```hcl
alerts = {
  backing_services = {
    postgres = { connections_percent = 70, enabled = true }
    redis    = { enabled = true }
    selector = "namespace=\"data\""
  }
}
```

Rules are keyed by the exporter's `instance` label. `selector` scopes all of
them, for example to one namespace. Managed services that only report to a
cloud provider, such as Amazon DocumentDB through CloudWatch, need an exporter
that turns those metrics into Prometheus ones first.

## Cluster types

| `cluster_type` | API server rules | etcd rules |
| --- | --- | --- |
| `eks`, `aks`, `gke` | No | No |
| `k3s` | Yes | No (k3s defaults to SQLite) |
| `openshift`, `generic` | Yes | Yes |

Override either with `alerts.control_plane`, for example
`{ etcd = true }` for k3s with embedded etcd.

## Alert catalog

Thresholds are starting points. Re-baseline them against your cluster's real
traffic. Override any rule by ID with `alerts.overrides`, or remove it with
`alerts.disabled_rules`.

| ID | Group | Alert | Fires when | Severity | Notes |
| --- | --- | --- | --- | --- | --- |
| `container_oom_killed` | pods | Container OOM killed | > 0 for 0s | warning | |
| `pod_crash_looping` | pods | Pod crash looping | > 5 for 1m | critical | |
| `pod_pending` | pods | Pod stuck pending | > 0 for 5m | warning | |
| `pod_waiting_failure` | pods | Pod cannot start | > 0 for 5m | critical | |
| `daemonset_not_ready` | workloads | DaemonSet pods not ready | > 0 for 15m | warning | |
| `deployment_rollout_stuck` | workloads | Deployment rollout stuck | > 0 for 5m | warning | |
| `deployment_unavailable` | workloads | Deployment has no available replicas | > 0 for 5m | critical | |
| `deployment_under_replicated` | workloads | Deployment under-replicated | > 0 for 10m | warning | |
| `hpa_at_max` | workloads | HPA pinned at max replicas | > 0.999 for 30m | warning | |
| `statefulset_under_replicated` | workloads | StatefulSet under-replicated | > 0 for 15m | warning | |
| `container_cpu_near_limit_critical` | resources | Container CPU at limit | > 90 for 15m | critical | |
| `container_cpu_near_limit_warning` | resources | Container CPU near limit | > 80 for 15m | warning | |
| `container_cpu_throttled` | resources | Container CPU throttled | > 25 for 15m | warning | |
| `container_ephemeral_storage_near_limit` | resources | Container ephemeral storage near limit | > 80 for 5m | critical | |
| `container_memory_near_limit_critical` | resources | Container memory at limit | > 90 for 5m | critical | |
| `container_memory_near_limit_warning` | resources | Container memory near limit | > 80 for 10m | warning | |
| `pvc_near_full_critical` | resources | PersistentVolumeClaim critically full | > 90 for 5m | critical | |
| `pvc_near_full_warning` | resources | PersistentVolumeClaim almost full | > 80 for 10m | warning | |
| `node_disk_full` | nodes | Node disk almost full | > 85 for 10m | critical | |
| `node_memory_high` | nodes | Node memory high | > 90 for 10m | warning | |
| `node_network_errors` | nodes | Node network errors | > 1 for 10m | warning | |
| `node_not_ready` | nodes | Node not ready | > 0 for 2m | critical | |
| `node_pressure` | nodes | Node under resource pressure | > 0 for 5m | warning | |
| `scrape_target_down` | nodes | Metrics target down | < 1 for 10m | warning | |
| `synthetic_check_failing` | synthetics | Synthetic check failing | < 1 for 2m | critical | Needs blackbox probes |
| `synthetic_check_slow` | synthetics | Synthetic check slow | > 5 for 10m | warning | Needs blackbox probes |
| `tls_certificate_expiring_critical` | synthetics | TLS certificate about to expire | < 3 for 1h | critical | Needs blackbox probes |
| `tls_certificate_expiring_warning` | synthetics | TLS certificate expiring soon | < 14 for 1h | warning | Needs blackbox probes |
| `apiserver_errors` | control-plane | API server error rate high | > 5 for 10m | critical | Needs `apiserver` metrics |
| `etcd_no_leader` | control-plane | etcd member has no leader | < 1 for 1m | critical | Needs `etcd` metrics |

Every alert carries the labels `cluster`, `severity` and `rule_id`, plus
any in `alerts.labels`. Each rule compares its query's value per series with
the threshold. A query that returns nothing, such as for a pod that no longer
exists, counts as healthy.

## Development

```bash
pre-commit install
pre-commit run --all-files
terraform init -backend=false && terraform test
```

The tests mock the Grafana provider, so they need no Grafana and no
credentials. See [CONTRIBUTING.md](CONTRIBUTING.md).

<!-- Generated by terraform-docs; its tables don't follow our Markdown rules. -->
<!-- markdownlint-disable -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15.0 |
| grafana | >= 4.0.0, < 5.0.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| alerts | ./modules/alerts | n/a |
| dashboards | ./modules/dashboards | n/a |
| notifications | ./modules/notifications | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_name | Name of the cluster, added to every alert as the `cluster` label and to rule titles. | `string` | n/a | yes |
| prometheus\_datasource\_uid | UID of the Prometheus-compatible Grafana datasource the alert rules query. | `string` | n/a | yes |
| alerts | Alert catalog settings. See modules/alerts for each field. | ```object({ apm = optional(object({ deploy_error_rate_percent = optional(number, 1) enabled = optional(bool, false) error_rate_percent = optional(number, 5) latency_avg_seconds = optional(number, 0.5) latency_p90_seconds = optional(number, 1) metric = optional(string, "http_server_request_duration_seconds") min_requests_per_second = optional(number, 0.1) route_label = optional(string, "http_route") selector = optional(string, "") service_label = optional(string, "job") status_label = optional(string, "http_response_status_code") traffic_drop_percent = optional(number, 75) }), {}) backing_services = optional(object({ mongodb = optional(object({ connections_percent = optional(number, 80) enabled = optional(bool, false) replication_lag_seconds = optional(number, 30) }), {}) mysql = optional(object({ connections_percent = optional(number, 80) enabled = optional(bool, false) replication_lag_seconds = optional(number, 30) }), {}) postgres = optional(object({ connections_percent = optional(number, 80) enabled = optional(bool, false) replication_lag_seconds = optional(number, 30) }), {}) rabbitmq = optional(object({ enabled = optional(bool, false) queue_depth = optional(number, 1000) unacked_messages = optional(number, 1000) }), {}) redis = optional(object({ enabled = optional(bool, false) memory_percent = optional(number, 90) }), {}) selector = optional(string, "") }), {}) control_plane = optional(object({ apiserver = optional(bool), etcd = optional(bool) }), {}) disabled_rules = optional(set(string), []) enabled = optional(bool, true) evaluation_interval_seconds = optional(number, 60) folder_title = optional(string) labels = optional(map(string), {}) overrides = optional(map(object({ paused = optional(bool) pending_period = optional(string) severity = optional(string) threshold = optional(number) })), {}) workload_selector = optional(string, "") })``` | `{}` | no |
| cluster\_type | Kind of cluster: eks, aks, gke, openshift, k3s or generic. Decides which control-plane rules apply. | `string` | `"generic"` | no |
| dashboards | Overview dashboard settings. Set `loki_datasource_uid` to add a logs row. See modules/dashboards. | ```object({ enabled = optional(bool, true) folder_title = optional(string) loki_datasource_uid = optional(string) refresh = optional(string, "1m") })``` | `{}` | no |
| notifications | Where alerts go. Turn on any combination of channels by setting them; see modules/notifications. Set `enabled = false` to manage contact points yourself. | ```object({ contact_point_name = optional(string) email = optional(object({ addresses = list(string) message = optional(string) single_email = optional(bool, true) subject = optional(string) })) enabled = optional(bool, true) icon_url = optional(string) manage_notification_policy = optional(bool, true) policy = optional(object({ critical_repeat_interval = optional(string, "1h") group_by = optional(list(string), ["grafana_folder", "alertname", "cluster"]) group_interval = optional(string, "5m") group_wait = optional(string, "30s") warning_repeat_interval = optional(string, "4h") }), {}) title_template = optional(string) })``` | `{}` | no |
| slack | Slack channel: an incoming webhook `url`, or a bot `token` and `recipient`. Null disables it. | ```object({ icon_url = optional(string) mention_channel = optional(string) recipient = optional(string) text = optional(string) title = optional(string) token = optional(string) url = optional(string) username = optional(string) })``` | `null` | no |
| teams | Microsoft Teams channel: a Teams Workflows webhook `url`. Null disables it. | ```object({ message = optional(string) section_title = optional(string) title = optional(string) url = string })``` | `null` | no |
| webex | Webex channel: an incoming `webhook_url`, or a bot `token` and `room_id`. Null disables it. | ```object({ api_url = optional(string) message = optional(string) room_id = optional(string) token = optional(string) webhook_url = optional(string) })``` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alert\_folder\_uid | UID of the Grafana folder that holds the alert rules, or null when alerts are off. |
| alert\_rule\_ids | IDs of the alert rules that were created. |
| contact\_point\_name | Name of the contact point, or null when notifications are off. |
| dashboard\_url | URL of the overview dashboard, or null when dashboards are off. |
| enabled\_channels | The notification channels that are turned on. |
<!-- END_TF_DOCS -->
<!-- markdownlint-enable -->
