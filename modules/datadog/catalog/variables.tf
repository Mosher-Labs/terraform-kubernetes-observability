variable "apm" {
  default     = {}
  description = "Service-level alerts from Datadog APM trace metrics: latency, error rate per service and per endpoint, traffic drops, and errors from a version rolled out in the last 30 minutes. Thresholds match modules/alerts. `span_name` is the operation name in the trace metrics (trace.<span_name>.hits), which depends on the tracer, such as `http.request`, `servlet.request` or `web.request`. `scope` is a Datadog tag filter such as `env:prod`; trace metrics carry no cluster tag. Rules only judge services with at least `min_requests_per_second`."
  type = object({
    deploy_error_rate_percent = optional(number, 1)
    enabled                   = optional(bool, false)
    error_rate_percent        = optional(number, 5)
    latency_avg_seconds       = optional(number, 0.5)
    latency_p90_seconds       = optional(number, 1)
    min_requests_per_second   = optional(number, 0.1)
    scope                     = optional(string, "")
    span_name                 = optional(string, "http.request")
    traffic_drop_percent      = optional(number, 75)
  })
}

variable "backing_services" {
  default     = {}
  description = "Alerts for databases, caches and queues from the Datadog Agent's integrations, one opt-in section per technology: postgres, mysql, redis, rabbitmq (OpenMetrics mode) and mongodb. Thresholds match modules/alerts. `scope` is a Datadog tag filter added to every metric rule, such as `kube_namespace:db`."
  type = object({
    mongodb = optional(object({
      connections_percent     = optional(number, 80)
      enabled                 = optional(bool, false)
      replication_lag_seconds = optional(number, 30)
    }), {})
    mysql = optional(object({
      connections_percent     = optional(number, 80)
      enabled                 = optional(bool, false)
      replication_lag_seconds = optional(number, 30)
    }), {})
    postgres = optional(object({
      connections_percent     = optional(number, 80)
      enabled                 = optional(bool, false)
      replication_lag_seconds = optional(number, 30)
    }), {})
    rabbitmq = optional(object({
      enabled          = optional(bool, false)
      queue_depth      = optional(number, 1000)
      unacked_messages = optional(number, 1000)
    }), {})
    redis = optional(object({
      enabled        = optional(bool, false)
      memory_percent = optional(number, 90)
    }), {})
    scope = optional(string, "")
  })
}

variable "cluster_name" {
  description = "Name of the cluster. Monitors are scoped to it with `cluster_tag`, tagged `cluster:<name>`, and their names start with it."
  type        = string
}

variable "cluster_tag" {
  default     = "kube_cluster_name"
  description = "Datadog tag that holds the cluster name. The Agent sets `kube_cluster_name` when its `clusterName` is set."
  type        = string
}

variable "control_plane" {
  default     = {}
  description = "Control-plane rules, off by default because managed clusters don't expose these metrics. `apiserver` needs the Agent's kube_apiserver_metrics check and `etcd` its etcd check. modules/stack's datadog_agent.control_plane_checks sets both up, including EKS and OpenShift control-plane monitoring."
  type = object({
    apiserver = optional(bool, false)
    etcd      = optional(bool, false)
  })
}

variable "disabled_rules" {
  default     = []
  description = "IDs of rules to leave out, such as `node_network_errors`. The same IDs as modules/alerts."
  type        = set(string)
}

variable "notification_handles" {
  default     = []
  description = "Datadog @-handles every monitor notifies, such as `@slack-homelab` or `@webhook-oncall`. Set up the integrations in Datadog first."
  type        = list(string)

  validation {
    condition     = alltrue([for h in var.notification_handles : startswith(h, "@")])
    error_message = "Each notification handle must start with @."
  }
}

variable "overrides" {
  default     = {}
  description = "Per-rule changes, keyed by rule ID: threshold, severity, window (the evaluation window, such as \"last_15m\", in place of Grafana's pending period), or a paused flag, which publishes the monitor as a draft that sends no notifications."
  type = map(object({
    paused    = optional(bool)
    severity  = optional(string)
    threshold = optional(number)
    window    = optional(string)
  }))

  validation {
    condition     = alltrue([for o in values(var.overrides) : o.severity == null || contains(["critical", "warning", "info"], coalesce(o.severity, "none"))])
    error_message = "An override's severity must be critical, warning or info."
  }

  validation {
    condition     = alltrue([for o in values(var.overrides) : o.window == null || can(regex("^last_[0-9]+[mhdw]$", coalesce(o.window, "none")))])
    error_message = "An override's window must look like last_15m, last_1h or last_1d."
  }
}

variable "renotify_interval_minutes" {
  default     = {}
  description = "Minutes before a monitor that is still alerting notifies again, per severity. 0 notifies once. Matches the Grafana notification policy's repeat intervals by default."
  type = object({
    critical = optional(number, 60)
    info     = optional(number, 0)
    warning  = optional(number, 240)
  })
}

variable "tags" {
  default     = []
  description = "Extra tags on every monitor, such as `team:platform`."
  type        = list(string)
}

variable "workload_scope" {
  default     = ""
  description = "Datadog tag filter added to every workload rule, to scope them. For example `NOT kube_namespace:kube-system`. Empty means all namespaces."
  type        = string
}
