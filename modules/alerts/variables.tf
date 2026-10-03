variable "apm" {
  default     = {}
  description = "Service-level alerts from a request-duration histogram: latency, error rate per service and per route, traffic drops, and errors right after a deploy. Defaults follow the OpenTelemetry HTTP semantic conventions as exported to Prometheus. Rules only judge services with at least `min_requests_per_second`."
  type = object({
    deploy_error_rate_percent = optional(number, 1)
    enabled                   = optional(bool, false)
    error_rate_percent        = optional(number, 5)
    latency_avg_seconds       = optional(number, 0.5)
    latency_p90_seconds       = optional(number, 1)
    metric                    = optional(string, "http_server_request_duration_seconds")
    min_requests_per_second   = optional(number, 0.1)
    route_label               = optional(string, "http_route")
    selector                  = optional(string, "")
    service_label             = optional(string, "job")
    status_label              = optional(string, "http_response_status_code")
    traffic_drop_percent      = optional(number, 75)
  })
}

variable "backing_services" {
  default     = {}
  description = "Alerts for databases, caches and queues, one opt-in section per technology: postgres, mysql, redis, rabbitmq and mongodb. Each reads its standard Prometheus exporter's metrics. `selector` scopes every rule, for example to one namespace."
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
    selector = optional(string, "")
  })
}

variable "cluster_name" {
  description = "Name of the cluster. Added to every alert as the `cluster` label and to each rule title, so alerts from several clusters stay distinguishable in one Grafana."
  type        = string
}

variable "cluster_type" {
  default     = "generic"
  description = "Kind of cluster: eks, aks, gke, openshift, k3s or generic. Managed control planes (eks, aks, gke) don't expose API server or etcd metrics, so those rules are left out for them."
  type        = string

  validation {
    condition     = contains(["eks", "aks", "gke", "openshift", "k3s", "generic"], var.cluster_type)
    error_message = "cluster_type must be one of eks, aks, gke, openshift, k3s or generic."
  }
}

variable "control_plane" {
  default     = {}
  description = "Override which control-plane metrics exist. Null keeps the cluster_type default. For example, k3s only has etcd metrics when it runs embedded etcd instead of the default SQLite."
  type = object({
    apiserver = optional(bool)
    etcd      = optional(bool)
  })
}

variable "custom_rules" {
  default     = {}
  description = "Your own rules, keyed by rule ID, in the catalog's shape: a PromQL `expr` returning the value to compare, `operator` (gt or lt) and `threshold`, `pending_period`, `severity`, `group`, `title`, `subject` and `summary`. They get the same labels, title prefix, overrides and disabled_rules support as catalog rules. workload_selector doesn't apply: write the full query. IDs can't reuse a catalog rule ID."
  type = map(object({
    expr           = string
    group          = string
    operator       = string
    pending_period = string
    severity       = string
    subject        = string
    summary        = string
    threshold      = number
    title          = string
  }))

  validation {
    condition     = alltrue([for r in values(var.custom_rules) : contains(["gt", "lt"], r.operator) && contains(["critical", "info", "warning"], r.severity)])
    error_message = "Each custom rule needs operator gt or lt, and severity critical, warning or info."
  }
}

variable "disabled_rules" {
  default     = []
  description = "IDs of catalog rules to leave out, such as `node_network_errors`."
  type        = set(string)
}

variable "evaluation_interval_seconds" {
  default     = 60
  description = "How often Grafana evaluates each rule group."
  type        = number
}

variable "folder_title" {
  default     = null
  description = "Title of the Grafana folder that holds the alert rules. Defaults to \"Kubernetes alerts (<cluster_name>)\"."
  type        = string
}

variable "heartbeat_enabled" {
  default     = false
  description = "Whether to create the heartbeat rule: it always fires while Grafana can query Prometheus, labeled heartbeat = \"true\", for modules/notifications to send to an outside heartbeat service."
  type        = bool
}

variable "labels" {
  default     = {}
  description = "Extra labels added to every alert, for routing or ownership."
  type        = map(string)
}

variable "overrides" {
  default     = {}
  description = "Per-rule changes, keyed by rule ID: threshold, pending period (how long the condition must hold before the alert fires, such as \"10m\"), severity, or a paused flag."
  type = map(object({
    paused         = optional(bool)
    pending_period = optional(string)
    severity       = optional(string)
    threshold      = optional(number)
  }))

  validation {
    condition     = alltrue([for o in values(var.overrides) : o.severity == null || contains(["critical", "warning", "info"], coalesce(o.severity, "none"))])
    error_message = "An override's severity must be critical, warning or info."
  }
}

variable "prometheus_datasource_uid" {
  description = "UID of the Prometheus-compatible Grafana datasource the rules query."
  type        = string
}

variable "workload_selector" {
  default     = ""
  description = "PromQL label matchers added to every workload rule, to scope them. For example `namespace!=\"kube-system\"`. Empty means all namespaces."
  type        = string
}
