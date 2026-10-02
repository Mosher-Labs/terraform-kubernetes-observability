variable "alerts" {
  default     = {}
  description = "Alert catalog settings. See modules/alerts for each field."
  type = object({
    apm = optional(object({
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
    }), {})
    control_plane               = optional(object({ apiserver = optional(bool), etcd = optional(bool) }), {})
    disabled_rules              = optional(set(string), [])
    enabled                     = optional(bool, true)
    evaluation_interval_seconds = optional(number, 60)
    folder_title                = optional(string)
    labels                      = optional(map(string), {})
    overrides = optional(map(object({
      paused         = optional(bool)
      pending_period = optional(string)
      severity       = optional(string)
      threshold      = optional(number)
    })), {})
    workload_selector = optional(string, "")
  })
}

variable "cluster_name" {
  description = "Name of the cluster, added to every alert as the `cluster` label and to rule titles."
  type        = string
}

variable "cluster_type" {
  default     = "generic"
  description = "Kind of cluster: eks, aks, gke, openshift, k3s or generic. Decides which control-plane rules apply."
  type        = string
}

variable "dashboards" {
  default     = {}
  description = "Overview dashboard settings. Set `loki_datasource_uid` to add a logs row. See modules/dashboards."
  type = object({
    enabled             = optional(bool, true)
    folder_title        = optional(string)
    loki_datasource_uid = optional(string)
    refresh             = optional(string, "1m")
  })
}

variable "notifications" {
  default     = {}
  description = "Where alerts go. Turn on any combination of channels by setting them; see modules/notifications. Set `enabled = false` to manage contact points yourself."
  type = object({
    contact_point_name = optional(string)
    email = optional(object({
      addresses    = list(string)
      message      = optional(string)
      single_email = optional(bool, true)
      subject      = optional(string)
    }))
    enabled                    = optional(bool, true)
    manage_notification_policy = optional(bool, true)
    policy = optional(object({
      critical_repeat_interval = optional(string, "1h")
      group_by                 = optional(list(string), ["grafana_folder", "alertname", "cluster"])
      group_interval           = optional(string, "5m")
      group_wait               = optional(string, "30s")
      warning_repeat_interval  = optional(string, "4h")
    }), {})
    title_template = optional(string)
  })
}

variable "prometheus_datasource_uid" {
  description = "UID of the Prometheus-compatible Grafana datasource the alert rules query."
  type        = string
}

variable "slack" {
  default     = null
  description = "Slack channel: an incoming webhook `url`, or a bot `token` and `recipient`. Null disables it."
  sensitive   = true
  type = object({
    mention_channel = optional(string)
    recipient       = optional(string)
    text            = optional(string)
    title           = optional(string)
    token           = optional(string)
    url             = optional(string)
    username        = optional(string)
  })
}

variable "teams" {
  default     = null
  description = "Microsoft Teams channel: a Teams Workflows webhook `url`. Null disables it."
  sensitive   = true
  type = object({
    message       = optional(string)
    section_title = optional(string)
    title         = optional(string)
    url           = string
  })
}

variable "webex" {
  default     = null
  description = "Webex channel: a bot `token` and `room_id`. Null disables it."
  sensitive   = true
  type = object({
    api_url = optional(string)
    message = optional(string)
    room_id = string
    token   = string
  })
}
