variable "apm" {
  default     = {}
  description = "Service-level alerts from request metrics. `enabled` turns the rules on and the rest tune them. `metric`, `route_label`, `service_label` and `status_label` name the Prometheus histogram and its labels (grafana). `span_name` names the Datadog trace metric, trace.<span_name>.hits (datadog). `scope` is a filter in the backend's own syntax, such as `namespace=\"prod\"` for grafana or `env:prod` for datadog. Rules only judge services with at least `min_requests_per_second`."
  type = object({
    deploy_error_rate_percent = optional(number, 1)
    enabled                   = optional(bool, false)
    error_rate_percent        = optional(number, 5)
    latency_avg_seconds       = optional(number, 0.5)
    latency_p90_seconds       = optional(number, 1)
    metric                    = optional(string, "http_server_request_duration_seconds")
    min_requests_per_second   = optional(number, 0.1)
    route_label               = optional(string, "http_route")
    scope                     = optional(string, "")
    service_label             = optional(string, "job")
    span_name                 = optional(string, "http.request")
    status_label              = optional(string, "http_response_status_code")
    traffic_drop_percent      = optional(number, 75)
  })
}

variable "backing_services" {
  default     = {}
  description = "Alerts for databases, caches and queues, one opt-in section per technology: postgres, mysql, redis, rabbitmq and mongodb. `scope` is a filter in the backend's own syntax, added to every backing-service rule."
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

variable "catalog" {
  description = "Which backend to render the catalog for: grafana (PromQL) or datadog (Datadog monitor queries)."
  type        = string

  validation {
    condition     = contains(["datadog", "grafana"], var.catalog)
    error_message = "catalog must be grafana or datadog."
  }
}

variable "cluster_scope" {
  default     = ""
  description = "The filter that limits every rule to one cluster, in Datadog's syntax, such as `kube_cluster_name:homelab`. Required for the datadog catalog. The grafana catalog ignores it."
  type        = string

  validation {
    condition     = var.catalog != "datadog" || var.cluster_scope != ""
    error_message = "The datadog catalog needs cluster_scope, such as kube_cluster_name:homelab."
  }
}

variable "control_plane" {
  default     = {}
  description = "Which control-plane metrics exist. Rules that need `apiserver` or `etcd` are left out when it is false. The caller decides, because managed clusters (EKS, AKS, GKE) don't expose them."
  type = object({
    apiserver = optional(bool, false)
    etcd      = optional(bool, false)
  })
}

variable "disabled_rules" {
  default     = []
  description = "IDs of rules to leave out, such as `node_network_errors`."
  type        = set(string)
}

variable "overrides" {
  default     = {}
  description = "Per-rule changes, keyed by rule ID: threshold, severity, a paused flag, `pending_period` (grafana) or `window` (datadog, such as \"last_15m\")."
  type = map(object({
    paused         = optional(bool)
    pending_period = optional(string)
    severity       = optional(string)
    threshold      = optional(number)
    window         = optional(string)
  }))
}

variable "workload_scope" {
  default     = ""
  description = "A filter in the backend's own syntax, added to every workload rule. For example `namespace!=\"kube-system\"` for grafana or `NOT kube_namespace:kube-system` for datadog. Empty means all namespaces."
  type        = string
}

variable "validate_rule_ids" {
  default     = true
  description = "Fail when `disabled_rules` or `overrides` name a rule that doesn't exist. Set it to false when the caller checks the IDs itself, as modules/alerts and modules/datadog do, so it can accept its own rules and report the error its own way."
  type        = bool
}
