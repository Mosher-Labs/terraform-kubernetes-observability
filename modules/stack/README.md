# stack

Installs the monitoring stack with Helm, each component behind its own flag,
all off by default:

| Flag | Installs | Notes |
| --- | --- | --- |
| `kube_prometheus_stack` | Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter | The metrics the alert catalog needs. Grafana's Prometheus datasource UID is `prometheus`. |
| `loki` | Loki, single binary, filesystem storage | Adds a `loki` datasource to Grafana when kube-prometheus-stack is installed too. |
| `alloy` | Grafana Alloy | Ships pod logs to Loki with `namespace`, `pod`, `container`, `app` and `cluster` labels. Needs `loki`, or `alloy.push_url`. |
| `blackbox_exporter` | Prometheus blackbox exporter | Probes `targets` for the synthetics alerts. Prometheus scrapes it when kube-prometheus-stack is installed. |
| `opentelemetry` | OpenTelemetry Operator, a collector and an Instrumentation | Turns apps' server spans into `http_server_request_duration_seconds` for the APM alerts and Services row. See [OpenTelemetry](#opentelemetry). |
| `datadog_agent` | Datadog Agent and Cluster Agent | For `modules/datadog`, instead of the Prometheus stack. See [Datadog Agent](#datadog-agent). |

Chart versions are pinned and can be overridden. Each component's `values` are
extra Helm values files, applied after the module's, so they win.

## Usage

```hcl
module "stack" {
  source = "github.com/Mosher-Labs/terraform-kubernetes-observability//modules/stack?ref=<commit-sha>"  # vX.Y.Z

  alloy = { enabled = true }
  blackbox_exporter = {
    enabled = true
    targets = [
      { name = "homepage", url = "https://example.com" },
      { module = "tcp_connect", name = "postgres", url = "postgres.db.svc.cluster.local:5432" },
    ]
  }
  cluster_name          = "lab"
  kube_prometheus_stack = { enabled = true }
  loki = {
    enabled      = true
    retention    = "336h"
    storage_size = "50Gi"
  }
  opentelemetry = { enabled = true }
}
```

The outputs wait for their Helm releases, so a module that uses
`prometheus_datasource_uid` runs after Grafana is installed.

## OpenTelemetry

`opentelemetry` installs the `opentelemetry-kube-stack` chart: the
OpenTelemetry Operator, one collector, and an Instrumentation named by the
`opentelemetry_instrumentation` output (`monitoring/opentelemetry` by
default). The collector's `spanmetrics` connector turns server spans into
`http_server_request_duration_seconds`, which Prometheus scrapes when
kube-prometheus-stack is installed too.

Apps opt in with a pod annotation:

| App | Annotation |
| --- | --- |
| Uses the OpenTelemetry SDK | `instrumentation.opentelemetry.io/inject-sdk: "monitoring/opentelemetry"` |
| Java, Node.js, Python, .NET | `instrumentation.opentelemetry.io/inject-<java\|nodejs\|python\|dotnet>: "monitoring/opentelemetry"` |
| Go binary you can't change | `instrumentation.opentelemetry.io/inject-go: "monitoring/opentelemetry"`, with `go_auto_instrumentation = true` |

`inject-sdk` adds only the `OTEL_*` environment (collector endpoint, service
name, resource attributes). The language agents also add the agent itself.

Each app shows up with `job="<namespace>/<service name>"` and its own
`namespace` label. The service name defaults to the workload name.

Things to know:

- **Go has no in-process agent.** Prefer the SDK: wrap the HTTP handler with
  `otelhttp` and set `http.route` from the matched route, or the metrics have
  no route label. The eBPF sidecar that `go_auto_instrumentation` enables runs
  privileged, fails on nodes with kernel lockdown (Secure Boot), and needs a
  binary that keeps its symbol table and DWARF.
- **The language agents export their own HTTP metrics too.** For Java,
  Node.js and Python, those duplicate the collector's series, so a service is
  counted twice. Set `OTEL_METRICS_EXPORTER=none` on those apps until the
  module filters them.
- **Agent images are pinned in the module.** The chart creates the
  Instrumentation before the operator's webhook is ready, so the webhook can't
  fill in its defaults. The images match the operator the chart ships; update
  them together with `chart_version`.

## Datadog Agent

`datadog_agent` installs Datadog's chart with kube-state metrics
(kubernetes_state_core), APM on port 8126 and a socket, and the Cluster Agent.
`logs` adds container logs. The Agent sets `kube_cluster_name` to
`cluster_name`, which `modules/datadog` scopes its monitors to.

```hcl
module "stack" {
  source = "github.com/Mosher-Labs/terraform-kubernetes-observability//modules/stack?ref=<commit-sha>"  # vX.Y.Z

  cluster_name = "lab"
  cluster_type = "k3s"
  datadog_agent = {
    api_key_secret_name = "datadog-secret"
    enabled             = true
  }
}
```

The API key comes from an existing Secret in `namespace` with an `api-key`
key, or from the sensitive `datadog_api_key` input.

`cluster_type` sets the chart's provider settings:

| `cluster_type` | Values |
| --- | --- |
| `eks`, `gke`, `generic` | The chart's defaults. |
| `aks` | `providers.aks.enabled`, for the kubelet's TLS. |
| `gke-autopilot` | `providers.gke.autopilot`, which drops what Autopilot refuses. |
| `k3s` | k3s's containerd socket, `/run/k3s/containerd/containerd.sock`, and no kubelet TLS verification (its certificate is self-signed). |
| `openshift` | SecurityContextConstraints for the Agents, CRI-O's socket, and no kubelet TLS verification. |

`control_plane_checks.enabled` collects API server metrics for
`modules/datadog`'s `control_plane.apiserver`: the chart's control-plane
monitoring on EKS and OpenShift, and a kube_apiserver_metrics cluster check
elsewhere. `control_plane_checks.etcd_prometheus_url` adds an etcd cluster
check, for etcd that serves metrics over plain HTTP, such as k3s's embedded
etcd with `--etcd-expose-metrics` on port 2381. GKE and AKS don't expose
either.

<!-- Generated by terraform-docs; its tables don't follow our Markdown rules. -->
<!-- markdownlint-disable -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15.0 |
| helm | >= 3.0.0, < 4.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| helm | >= 3.0.0, < 4.0.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.alloy](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.blackbox_exporter](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.datadog_agent](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.kube_prometheus_stack](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.loki](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.opentelemetry](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_name | Name of the cluster, added to logs as the `cluster` label so they match the alerts' `cluster` label. | `string` | n/a | yes |
| alloy | Grafana Alloy, which ships pod logs to Loki. It needs `loki.enabled`, or `push_url` for a Loki installed elsewhere. `values` are extra Helm values files, applied after the module's. | ```object({ chart_version = optional(string, "1.13.0") enabled = optional(bool, false) push_url = optional(string) release_name = optional(string, "alloy") values = optional(list(string), []) })``` | `{}` | no |
| blackbox\_exporter | The Prometheus blackbox exporter, for synthetic checks from inside the cluster. Each target is probed on the module's schedule; with kube\_prometheus\_stack enabled, Prometheus scrapes the results. `values` are extra Helm values files. | ```object({ chart_version = optional(string, "11.19.1") enabled = optional(bool, false) release_name = optional(string, "blackbox-exporter") targets = optional(list(object({ interval = optional(string, "60s") module = optional(string, "http_2xx") name = string url = string })), []) values = optional(list(string), []) })``` | `{}` | no |
| cluster\_type | Kind of cluster: eks, aks, gke, gke-autopilot, openshift, k3s or generic. Sets the Datadog Agent's provider-specific values, such as k3s's containerd socket. | `string` | `"generic"` | no |
| create\_namespace | Whether Helm creates the namespace. | `bool` | `true` | no |
| datadog\_agent | The Datadog Agent and Cluster Agent, for modules/datadog. It collects kube-state metrics (kubernetes\_state\_core), kubelet and host metrics, and APM traces (port 8126 and a socket); `logs` adds container logs. `api_key_secret_name` names an existing Secret in `namespace` with the API key under `api-key`, or set `datadog_api_key`. `control_plane_checks.enabled` adds API server metrics (EKS and OpenShift control-plane monitoring, or a kube\_apiserver\_metrics cluster check elsewhere); `etcd_prometheus_url` adds an etcd cluster check, for self-managed etcd that serves metrics over plain HTTP. `values` are extra Helm values files. | ```object({ api_key_secret_name = optional(string) apm = optional(bool, true) chart_version = optional(string, "3.251.1") control_plane_checks = optional(object({ enabled = optional(bool, false) etcd_prometheus_url = optional(string) }), {}) enabled = optional(bool, false) logs = optional(bool, false) release_name = optional(string, "datadog") site = optional(string, "datadoghq.com") values = optional(list(string), []) })``` | `{}` | no |
| datadog\_api\_key | Datadog API key, when datadog\_agent.api\_key\_secret\_name isn't set. The chart stores it in a Secret. | `string` | `null` | no |
| kube\_prometheus\_stack | kube-prometheus-stack: Prometheus, Alertmanager, Grafana, kube-state-metrics and node-exporter, which the alert catalog needs. `values` are extra Helm values files, applied after the module's. | ```object({ chart_version = optional(string, "91.9.0") enabled = optional(bool, false) release_name = optional(string, "kube-prometheus-stack") values = optional(list(string), []) })``` | `{}` | no |
| loki | Loki in single-binary mode with filesystem storage, sized for small clusters. For anything larger, override the deployment mode and storage through `values`. | ```object({ chart_version = optional(string, "7.3.0") enabled = optional(bool, false) release_name = optional(string, "loki") retention = optional(string, "168h") storage_size = optional(string, "10Gi") values = optional(list(string), []) })``` | `{}` | no |
| namespace | Namespace for every component. | `string` | `"monitoring"` | no |
| opentelemetry | The OpenTelemetry Operator, a collector that turns server spans into `http_server_request_duration_seconds` for the APM alerts and Services row, and an Instrumentation that apps opt into with a pod annotation. `go_auto_instrumentation` turns on the operator's eBPF sidecar for Go binaries, which runs privileged and fails on nodes with kernel lockdown. `values` are extra Helm values files. | ```object({ chart_version = optional(string, "0.24.0") collector_image = optional(string, "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.160.0") enabled = optional(bool, false) go_auto_instrumentation = optional(bool, false) release_name = optional(string, "opentelemetry") values = optional(list(string), []) })``` | `{}` | no |
| timeout\_seconds | How long Helm waits for each release to become ready. | `number` | `600` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| grafana\_admin\_secret | Namespace and name of the Secret holding the Grafana admin user and password, when kube\_prometheus\_stack is enabled. |
| grafana\_service | In-cluster URL of Grafana, when kube\_prometheus\_stack is enabled. |
| installed | The components this module installed. |
| loki\_datasource\_uid | UID of the Loki datasource added to Grafana, when loki and kube\_prometheus\_stack are both enabled. |
| loki\_url | In-cluster URL of Loki, when loki is enabled. |
| opentelemetry\_instrumentation | The `<namespace>/<name>` of the Instrumentation, for pod annotations such as `instrumentation.opentelemetry.io/inject-sdk`, when opentelemetry is enabled. |
| prometheus\_datasource\_uid | UID of Grafana's Prometheus datasource, for the root module's prometheus\_datasource\_uid, when kube\_prometheus\_stack is enabled. |
<!-- END_TF_DOCS -->
<!-- markdownlint-enable -->
