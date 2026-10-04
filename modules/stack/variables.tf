variable "alloy" {
  default     = {}
  description = "Grafana Alloy, which ships pod logs to Loki. It needs `loki.enabled`, or `push_url` for a Loki installed elsewhere. `values` are extra Helm values files, applied after the module's."
  type = object({
    chart_version = optional(string, "1.13.0")
    enabled       = optional(bool, false)
    push_url      = optional(string)
    release_name  = optional(string, "alloy")
    values        = optional(list(string), [])
  })
}

variable "blackbox_exporter" {
  default     = {}
  description = "The Prometheus blackbox exporter, for synthetic checks from inside the cluster. Each target is probed on the module's schedule; with kube_prometheus_stack enabled, Prometheus scrapes the results. `values` are extra Helm values files."
  type = object({
    chart_version = optional(string, "11.19.1")
    enabled       = optional(bool, false)
    release_name  = optional(string, "blackbox-exporter")
    targets = optional(list(object({
      interval = optional(string, "60s")
      module   = optional(string, "http_2xx")
      name     = string
      url      = string
    })), [])
    values = optional(list(string), [])
  })
}

variable "cluster_name" {
  description = "Name of the cluster, added to logs as the `cluster` label so they match the alerts' `cluster` label."
  type        = string
}

variable "create_namespace" {
  default     = true
  description = "Whether Helm creates the namespace."
  type        = bool
}

variable "kube_prometheus_stack" {
  default     = {}
  description = "kube-prometheus-stack: Prometheus, Alertmanager, Grafana, kube-state-metrics and node-exporter, which the alert catalog needs. `values` are extra Helm values files, applied after the module's."
  type = object({
    chart_version = optional(string, "91.9.0")
    enabled       = optional(bool, false)
    release_name  = optional(string, "kube-prometheus-stack")
    values        = optional(list(string), [])
  })
}

variable "loki" {
  default     = {}
  description = "Loki in single-binary mode with filesystem storage, sized for small clusters. For anything larger, override the deployment mode and storage through `values`."
  type = object({
    chart_version = optional(string, "7.3.0")
    enabled       = optional(bool, false)
    release_name  = optional(string, "loki")
    retention     = optional(string, "168h")
    storage_size  = optional(string, "10Gi")
    values        = optional(list(string), [])
  })
}

variable "namespace" {
  default     = "monitoring"
  description = "Namespace for every component."
  type        = string
}

variable "opentelemetry" {
  default     = {}
  description = "The OpenTelemetry Operator, a collector that turns server spans into `http_server_request_duration_seconds` for the APM alerts and Services row, and an Instrumentation that apps opt into with a pod annotation. `go_auto_instrumentation` turns on the operator's eBPF sidecar for Go binaries, which runs privileged and fails on nodes with kernel lockdown. `values` are extra Helm values files."
  type = object({
    chart_version           = optional(string, "0.24.0")
    collector_image         = optional(string, "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:0.160.0")
    enabled                 = optional(bool, false)
    go_auto_instrumentation = optional(bool, false)
    release_name            = optional(string, "opentelemetry")
    values                  = optional(list(string), [])
  })
}

variable "timeout_seconds" {
  default     = 600
  description = "How long Helm waits for each release to become ready."
  type        = number
}
