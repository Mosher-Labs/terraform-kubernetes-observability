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
- **Notifications** to Slack, email, Webex and Teams. Each channel is optional
  and independent.
- **Submodules you can use on their own:** `modules/alerts` and
  `modules/notifications`.

Planned: opt-in installs of kube-prometheus-stack, Loki and the blackbox
exporter, one flag each; dashboards; synthetic checks; service-level (APM) and
backing-service alerts.

## Usage

```hcl
provider "grafana" {
  url  = "https://grafana.example.com"
  auth = var.grafana_token
}

module "observability" {
  source = "github.com/Mosher-Labs/terraform-kubernetes-observability?ref=<commit-sha>"  # vX.Y.Z

  cluster_name              = "homelab"
  cluster_type              = "k3s"
  prometheus_datasource_uid = "prometheus"

  alerts = {
    workload_selector = "namespace!~\"kube-system\""
    overrides = {
      node_disk_full = { threshold = 90 }
    }
  }

  slack = { url = var.slack_webhook_url }

  notifications = {
    email = { addresses = ["oncall@example.com"] }
  }
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

### Notification policy

Grafana has one notification policy tree per organization. By default the
module manages that tree: everything goes to this module's contact point, and
critical alerts repeat more often than warnings. If something else already
manages your policies, set `notifications.manage_notification_policy = false`
and route on the `cluster` and `severity` labels yourself.

### Message titles

Slack and Teams titles and email subjects start with 🔴 FIRING or ✅ RESOLVED,
then the alert name, for example `🔴 FIRING (2): [homelab] Pod crash looping`.
Grafana posts a resolve as a new message, not as a reply to the original, so
the title is what pairs them up. Change it with `notifications.title_template`,
or set a channel's own `title` or `subject`.

Grafana posts to Slack as "Grafana" unless you set `slack.username`, for
example to your Slack app's name. With a bot token, that needs the
`chat:write.customize` scope.

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
| `pod_crash_looping` | pods | Pod crash looping | > 5 for 1m | critical | |
| `container_oom_killed` | pods | Container OOM killed | > 0 for 0s | warning | |
| `pod_waiting_failure` | pods | Pod cannot start | > 0 for 5m | critical | |
| `pod_pending` | pods | Pod stuck pending | > 0 for 5m | warning | |
| `deployment_unavailable` | workloads | Deployment has no available replicas | > 0 for 5m | critical | |
| `deployment_under_replicated` | workloads | Deployment under-replicated | > 0 for 10m | warning | |
| `deployment_rollout_stuck` | workloads | Deployment rollout stuck | > 0 for 5m | warning | |
| `statefulset_under_replicated` | workloads | StatefulSet under-replicated | > 0 for 15m | warning | |
| `daemonset_not_ready` | workloads | DaemonSet pods not ready | > 0 for 15m | warning | |
| `hpa_at_max` | workloads | HPA pinned at max replicas | > 0.999 for 30m | warning | |
| `container_memory_near_limit_warning` | resources | Container memory near limit | > 80 for 10m | warning | |
| `container_memory_near_limit_critical` | resources | Container memory at limit | > 90 for 5m | critical | |
| `container_cpu_near_limit_warning` | resources | Container CPU near limit | > 80 for 15m | warning | |
| `container_cpu_near_limit_critical` | resources | Container CPU at limit | > 90 for 15m | critical | |
| `container_cpu_throttled` | resources | Container CPU throttled | > 25 for 15m | warning | |
| `container_ephemeral_storage_near_limit` | resources | Container ephemeral storage near limit | > 80 for 5m | critical | |
| `pvc_near_full_warning` | resources | PersistentVolumeClaim almost full | > 80 for 10m | warning | |
| `pvc_near_full_critical` | resources | PersistentVolumeClaim critically full | > 90 for 5m | critical | |
| `node_not_ready` | nodes | Node not ready | > 0 for 2m | critical | |
| `node_pressure` | nodes | Node under resource pressure | > 0 for 5m | warning | |
| `node_disk_full` | nodes | Node disk almost full | > 85 for 10m | critical | |
| `node_memory_high` | nodes | Node memory high | > 90 for 10m | warning | |
| `node_network_errors` | nodes | Node network errors | > 1 for 10m | warning | |
| `scrape_target_down` | nodes | Metrics target down | < 1 for 10m | warning | |
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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.5.0 |
| grafana | >= 4.0.0, < 5.0.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| alerts | ./modules/alerts | n/a |
| notifications | ./modules/notifications | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_name | Name of the cluster, added to every alert as the `cluster` label and to rule titles. | `string` | n/a | yes |
| prometheus\_datasource\_uid | UID of the Prometheus-compatible Grafana datasource the alert rules query. | `string` | n/a | yes |
| alerts | Alert catalog settings. See modules/alerts for each field. | ```object({ enabled = optional(bool, true) control_plane = optional(object({ apiserver = optional(bool), etcd = optional(bool) }), {}) disabled_rules = optional(set(string), []) evaluation_interval_seconds = optional(number, 60) folder_title = optional(string) labels = optional(map(string), {}) overrides = optional(map(object({ threshold = optional(number) for = optional(string) severity = optional(string) paused = optional(bool) })), {}) workload_selector = optional(string, "") })``` | `{}` | no |
| cluster\_type | Kind of cluster: eks, aks, gke, openshift, k3s or generic. Decides which control-plane rules apply. | `string` | `"generic"` | no |
| notifications | Where alerts go. Turn on any combination of channels by setting them; see modules/notifications. Set `enabled = false` to manage contact points yourself. | ```object({ enabled = optional(bool, true) contact_point_name = optional(string) manage_notification_policy = optional(bool, true) title_template = optional(string) email = optional(object({ addresses = list(string) single_email = optional(bool, true) subject = optional(string) message = optional(string) })) policy = optional(object({ group_by = optional(list(string), ["grafana_folder", "alertname", "cluster"]) group_wait = optional(string, "30s") group_interval = optional(string, "5m") critical_repeat_interval = optional(string, "1h") warning_repeat_interval = optional(string, "4h") }), {}) })``` | `{}` | no |
| slack | Slack channel: an incoming webhook `url`, or a bot `token` and `recipient`. Null disables it. | ```object({ url = optional(string) token = optional(string) recipient = optional(string) username = optional(string) mention_channel = optional(string) title = optional(string) text = optional(string) })``` | `null` | no |
| teams | Microsoft Teams channel: a Teams Workflows webhook `url`. Null disables it. | ```object({ url = string title = optional(string) section_title = optional(string) message = optional(string) })``` | `null` | no |
| webex | Webex channel: a bot `token` and `room_id`. Null disables it. | ```object({ token = string room_id = string api_url = optional(string) message = optional(string) })``` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alert\_folder\_uid | UID of the Grafana folder that holds the alert rules, or null when alerts are off. |
| alert\_rule\_ids | IDs of the alert rules that were created. |
| contact\_point\_name | Name of the contact point, or null when notifications are off. |
| enabled\_channels | The notification channels that are turned on. |
<!-- END_TF_DOCS -->
