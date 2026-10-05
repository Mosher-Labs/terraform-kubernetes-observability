# datadog

Creates the alert catalog as Datadog monitors, and their notification
channels, instead of Grafana alert rules. Use it in place of the root module
when your cluster sends metrics to Datadog. It's called on its own, so the root
module never needs the Datadog provider. `modules/stack`'s `datadog_agent` flag
installs the Agent it reads from.

Rule IDs, titles, severities and default thresholds match `modules/alerts`, so
the same `overrides` and `disabled_rules` work on either backend. The `apm`,
`backing_services` and `control_plane` inputs mirror `modules/alerts`.

## Usage

```hcl
module "datadog_alerts" {
  source = "github.com/Mosher-Labs/terraform-kubernetes-observability//modules/datadog?ref=<commit-sha>"  # vX.Y.Z

  apm              = { enabled = true, scope = "env:prod" }
  backing_services = { postgres = { enabled = true } }
  cluster_name     = "prod"
  notifications = {
    email = { addresses = ["oncall@example.com"] }
    slack = { account_name = "example", channel = "prod-alerts" }
    webex = { room_id = var.webex_room_id, token = var.webex_bot_token }
  }
  overrides = {
    node_disk_full = { threshold = 90 }
  }
  workload_scope = "NOT kube_namespace:kube-system"
}
```

See [examples/datadog](../../examples/datadog), which also installs the Agent.

## Notifications

Each channel in `notifications` is created in Datadog and added to every
monitor's message as an @-handle. `notification_handles` adds raw handles, such
as `@pagerduty-oncall`. Every message starts with 🔴 FIRING or ✅ RESOLVED, like
the Grafana backend's titles.

| Channel | Datadog resource | Handle | Before you start |
| --- | --- | --- | --- |
| `email` | none | `@<address>` | Nothing. |
| `slack` | `datadog_integration_slack_channel` | `@slack-<account>-<channel>` | Install the Datadog app in the workspace from Datadog's Slack integration tile, once. `account_name` is the workspace's name in that tile. |
| `teams` | `datadog_integration_ms_teams_workflows_webhook_handle` | `@teams-<name>` | Create a Teams Workflows webhook for the channel, as for the Grafana backend. |
| `webex` | `datadog_webhook` | `@webhook-<name>` | An incoming webhook URL, or a bot token and room ID. Datadog has no Webex integration, so this is a custom webhook. A bot token is stored as a secret webhook variable. |

`name` sets the Teams and Webex handle names, and defaults to
`kubernetes-<cluster_name>`.

Slack shows each alert's graph. Webex can't show images inline, so its messages
link the graph instead ("📈 View graph"). With a Webex bot, service checks,
which have no graph, go to a text-only webhook (`@webhook-<name>-text`).

If the Slack channel was already added in Datadog's Slack tile, `apply` fails
with "Channel is already configured". Import it first:

```bash
terraform import 'module.datadog_alerts.datadog_integration_slack_channel.this[0]' '<account_name>:#<channel>'
```

## How the catalog maps to Datadog

- Each rule is a multi-alert monitor, grouped like the Grafana rule (per pod,
  per deployment, per node). Severity sets the priority (critical 1, warning 3,
  info 5) and a `severity` tag.
- Grafana's pending period becomes the evaluation `window`. Rules that fire
  above a threshold use `min()` over the window, so the condition must hold for
  the whole window. Override it per rule with `overrides.<id>.window`.
- `scrape_target_down` and the `*_down` backing-service rules are service-check
  monitors. Their threshold is the number of consecutive failed check runs; the
  Agent runs each check every 15 seconds, so 8 is about 2 minutes. `window`
  and the backing-service `scope` don't apply to them.
- `paused` publishes the monitor as a draft, which sends no notifications.
- Rules where zero means healthy wrap their metric in `default_zero()`, so a pod
  that no longer exists resolves. No monitor resolves on missing data.
- `cluster_not_reporting` exists only here. Datadog runs outside the cluster,
  so it alerts when the cluster stops sending data, which is the heartbeat's job
  on the Grafana backend.

| Rules | Datadog source |
| --- | --- |
| Pods, workloads, PersistentVolumes | `kubernetes_state.*` from the Agent's kubernetes_state_core check |
| Resources, PVC inodes, kubelet certificates | `kubernetes.*` from the kubelet check |
| Nodes | `system.*` host metrics (disk, inodes, memory, network) and `kubernetes_state.node.*` |
| `node_clock_skew`, `node_clock_not_synchronising` | The Agent's NTP check: `ntp.offset`, and the `ntp.in_sync` service check |
| `node_systemd_service_failed` | The `systemd.unit.state` service check. Needs the Agent's systemd check, which is off by default. |
| `scrape_target_down` | The `datadog.agent.check_status` service check, per check and host |
| `apiserver_errors`, `apiserver_client_certificate_expiring`, `etcd_no_leader` | The kube_apiserver_metrics and etcd checks. Off until `control_plane` turns them on. |
| APM | `trace.<span_name>.hits`, `.errors` and the `trace.<span_name>` latency distribution, by `service` (and `resource_name` per endpoint) |
| Postgres, MySQL, MongoDB, Redis | `postgresql.*`, `mysql.*`, `mongodb.*`, `redis.*`, and each integration's `can_connect` service check |
| RabbitMQ | `rabbitmq.*` from the integration's OpenMetrics mode (rabbitmq_prometheus plugin) |

These rules have no monitor here:

| Rule | Why |
| --- | --- |
| `notification_delivery_failing` | Watches Grafana's notification pipeline. |
| `prometheus_config_reload_failed`, `prometheus_not_ingesting`, `prometheus_rule_failures` | Prometheus' own health. This backend has no Prometheus; `cluster_not_reporting` catches the Agent going quiet. |
| `synthetic_check_failing`, `synthetic_check_slow`, `tls_certificate_expiring_critical`, `tls_certificate_expiring_warning` | Datadog Synthetics, tracked in an issue. |

### Known differences from the Grafana backend

- `service_traffic_drop` compares traffic with the same time an hour earlier,
  not with the last hour's average.
- `service_errors_after_deploy` uses Datadog's `version` tag: it judges a
  version that had no traffic 30 minutes ago, not any service in a namespace
  where a deployment changed.
- APM trace metrics carry no cluster tag, so `apm.scope` (such as `env:prod`)
  scopes them instead.
- `deployment_unavailable` alerts when more than 99% of desired replicas are
  unavailable, and `node_not_ready` uses a 5-minute window.
- `container_ephemeral_storage_near_limit` is per pod; the kubelet reports
  ephemeral storage per pod.
- `node_clock_not_synchronising` uses the NTP check's `ntp.in_sync`, which
  fails when the offset from Datadog's NTP servers passes the check's limit,
  not the kernel's sync status. The NTP check runs every 15 minutes, so one
  failed run alerts.
- `apiserver_client_certificate_expiring` counts requests made with a client
  certificate that expires within 7 days, so its threshold is a request count
  (0), not seconds.
- `kubelet_certificate_expiring` reads the client certificate's TTL only.

## Development

`modules/datadog/catalog` renders every monitor argument without the Datadog
provider, and the root module's tests check it. `tests/` here checks the
monitor and notification resources:

```bash
cd modules/datadog
terraform init -backend=false && terraform test
```

<!-- Generated by terraform-docs; its tables don't follow our Markdown rules. -->
<!-- markdownlint-disable -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15.0 |
| datadog | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| datadog | >= 4.0.0, < 5.0.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| catalog | ./catalog | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [datadog_integration_ms_teams_workflows_webhook_handle.this](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/integration_ms_teams_workflows_webhook_handle) | resource |
| [datadog_integration_slack_channel.this](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/integration_slack_channel) | resource |
| [datadog_monitor.this](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/monitor) | resource |
| [datadog_webhook.webex](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/webhook) | resource |
| [datadog_webhook.webex_text](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/webhook) | resource |
| [datadog_webhook_custom_variable.webex_token](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/webhook_custom_variable) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_name | Name of the cluster. Monitors are scoped to it with `cluster_tag`, tagged `cluster:<name>`, and their names start with it. | `string` | n/a | yes |
| apm | Service-level alerts from Datadog APM trace metrics: latency, error rate per service and per endpoint, traffic drops, and errors from a version rolled out in the last 30 minutes. Thresholds match modules/alerts. `span_name` is the operation name in the trace metrics (trace.<span\_name>.hits), which depends on the tracer, such as `http.request`, `servlet.request` or `web.request`. `scope` is a Datadog tag filter such as `env:prod`; trace metrics carry no cluster tag. Rules only judge services with at least `min_requests_per_second`. | ```object({ deploy_error_rate_percent = optional(number, 1) enabled = optional(bool, false) error_rate_percent = optional(number, 5) latency_avg_seconds = optional(number, 0.5) latency_p90_seconds = optional(number, 1) min_requests_per_second = optional(number, 0.1) scope = optional(string, "") span_name = optional(string, "http.request") traffic_drop_percent = optional(number, 75) })``` | `{}` | no |
| backing\_services | Alerts for databases, caches and queues from the Datadog Agent's integrations, one opt-in section per technology: postgres, mysql, redis, rabbitmq (OpenMetrics mode) and mongodb. Thresholds match modules/alerts. `scope` is a Datadog tag filter added to every metric rule, such as `kube_namespace:db`. | ```object({ mongodb = optional(object({ connections_percent = optional(number, 80) enabled = optional(bool, false) replication_lag_seconds = optional(number, 30) }), {}) mysql = optional(object({ connections_percent = optional(number, 80) enabled = optional(bool, false) replication_lag_seconds = optional(number, 30) }), {}) postgres = optional(object({ connections_percent = optional(number, 80) enabled = optional(bool, false) replication_lag_seconds = optional(number, 30) }), {}) rabbitmq = optional(object({ enabled = optional(bool, false) queue_depth = optional(number, 1000) unacked_messages = optional(number, 1000) }), {}) redis = optional(object({ enabled = optional(bool, false) memory_percent = optional(number, 90) }), {}) scope = optional(string, "") })``` | `{}` | no |
| cluster\_tag | Datadog tag that holds the cluster name. The Agent sets `kube_cluster_name` when its `clusterName` is set. | `string` | `"kube_cluster_name"` | no |
| control\_plane | Control-plane rules, off by default because managed clusters don't expose these metrics. `apiserver` needs the Agent's kube\_apiserver\_metrics check and `etcd` its etcd check. modules/stack's datadog\_agent.control\_plane\_checks sets both up, including EKS and OpenShift control-plane monitoring. | ```object({ apiserver = optional(bool, false) etcd = optional(bool, false) })``` | `{}` | no |
| disabled\_rules | IDs of rules to leave out, such as `node_network_errors`. The same IDs as modules/alerts. | `set(string)` | `[]` | no |
| notification\_handles | Extra Datadog @-handles every monitor notifies, on top of those from `notifications`, such as `@pagerduty-oncall`. | `list(string)` | `[]` | no |
| notifications | Notification channels, created in Datadog and added to every monitor as @-handles. Turn on any combination by setting them; `notification_handles` adds raw handles on top. - `email`: addresses, notified as `@<address>`. - `slack`: a channel in a Slack workspace already connected to Datadog (install the Datadog app from Datadog's Slack integration tile first). `account_name` is the workspace name in that tile. - `teams`: a Microsoft Teams Workflows webhook `url`, as a Datadog Teams handle. - `webex`: an incoming `webhook_url`, or a bot `token` and `room_id`, sent through a Datadog webhook. Datadog has no Webex integration. `name` sets the handle name; it defaults to `kubernetes-<cluster_name>`. | ```object({ email = optional(object({ addresses = list(string) })) slack = optional(object({ account_name = string channel = string })) teams = optional(object({ name = optional(string) url = string })) webex = optional(object({ api_url = optional(string, "https://webexapis.com/v1/messages") name = optional(string) room_id = optional(string) token = optional(string) webhook_url = optional(string) })) })``` | `{}` | no |
| overrides | Per-rule changes, keyed by rule ID: threshold, severity, window (the evaluation window, such as "last\_15m", in place of Grafana's pending period), or a paused flag, which publishes the monitor as a draft that sends no notifications. | ```map(object({ paused = optional(bool) severity = optional(string) threshold = optional(number) window = optional(string) }))``` | `{}` | no |
| renotify\_interval\_minutes | Minutes before a monitor that is still alerting notifies again, per severity. 0 notifies once. Matches the Grafana notification policy's repeat intervals by default. | ```object({ critical = optional(number, 60) info = optional(number, 0) warning = optional(number, 240) })``` | `{}` | no |
| tags | Extra tags on every monitor, such as `team:platform`. | `list(string)` | `[]` | no |
| workload\_scope | Datadog tag filter added to every workload rule, to scope them. For example `NOT kube_namespace:kube-system`. Empty means all namespaces. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| monitor\_ids | Datadog monitor IDs, keyed by rule ID. |
| monitors | The monitors as created: name, query, threshold, window, severity and group, keyed by rule ID. |
| rule\_ids | IDs of the monitors that were created, after disabled\_rules is applied. |
| skipped\_rules | modules/alerts catalog rules that have no Datadog monitor, with the reason and what to use instead. |
<!-- END_TF_DOCS -->
