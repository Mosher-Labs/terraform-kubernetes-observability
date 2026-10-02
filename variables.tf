variable "alerts" {
  description = "Alert catalog settings. See modules/alerts for each field."
  type = object({
    enabled                     = optional(bool, true)
    control_plane               = optional(object({ apiserver = optional(bool), etcd = optional(bool) }), {})
    disabled_rules              = optional(set(string), [])
    evaluation_interval_seconds = optional(number, 60)
    folder_title                = optional(string)
    labels                      = optional(map(string), {})
    overrides = optional(map(object({
      threshold = optional(number)
      for       = optional(string)
      severity  = optional(string)
      paused    = optional(bool)
    })), {})
    workload_selector = optional(string, "")
  })
  default = {}
}

variable "cluster_name" {
  description = "Name of the cluster, added to every alert as the `cluster` label and to rule titles."
  type        = string
}

variable "cluster_type" {
  description = "Kind of cluster: eks, aks, gke, openshift, k3s or generic. Decides which control-plane rules apply."
  type        = string
  default     = "generic"
}

variable "notifications" {
  description = "Where alerts go. Turn on any combination of channels by setting them; see modules/notifications. Set `enabled = false` to manage contact points yourself."
  type = object({
    enabled                    = optional(bool, true)
    contact_point_name         = optional(string)
    manage_notification_policy = optional(bool, true)
    email = optional(object({
      addresses    = list(string)
      single_email = optional(bool, true)
      subject      = optional(string)
      message      = optional(string)
    }))
    policy = optional(object({
      group_by                 = optional(list(string), ["grafana_folder", "alertname", "cluster"])
      group_wait               = optional(string, "30s")
      group_interval           = optional(string, "5m")
      critical_repeat_interval = optional(string, "1h")
      warning_repeat_interval  = optional(string, "4h")
    }), {})
  })
  default = {}
}

variable "prometheus_datasource_uid" {
  description = "UID of the Prometheus-compatible Grafana datasource the alert rules query."
  type        = string
}

variable "slack" {
  description = "Slack channel: an incoming webhook `url`, or a bot `token` and `recipient`. Null disables it."
  type = object({
    url             = optional(string)
    token           = optional(string)
    recipient       = optional(string)
    username        = optional(string)
    mention_channel = optional(string)
    title           = optional(string)
    text            = optional(string)
  })
  default   = null
  sensitive = true
}

variable "teams" {
  description = "Microsoft Teams channel: a Teams Workflows webhook `url`. Null disables it."
  type = object({
    url           = string
    title         = optional(string)
    section_title = optional(string)
    message       = optional(string)
  })
  default   = null
  sensitive = true
}

variable "webex" {
  description = "Webex channel: a bot `token` and `room_id`. Null disables it."
  type = object({
    token   = string
    room_id = string
    api_url = optional(string)
    message = optional(string)
  })
  default   = null
  sensitive = true
}
