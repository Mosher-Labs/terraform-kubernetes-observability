variable "contact_point_name" {
  description = "Name of the Grafana contact point that holds every enabled channel."
  type        = string
}

variable "email" {
  default     = null
  description = "Email channel. Null disables it. Grafana must have SMTP configured."
  type = object({
    addresses    = list(string)
    message      = optional(string)
    single_email = optional(bool, true)
    subject      = optional(string)
  })
}

variable "manage_notification_policy" {
  default     = true
  description = "Whether to manage the Grafana organization's notification policy tree. Grafana has one tree per organization, so this replaces any policies created elsewhere. Set false to route alerts yourself, using the `cluster` and `severity` labels."
  type        = bool
}

variable "policy" {
  default     = {}
  description = "Grouping and timing for the notification policy. Critical alerts repeat more often than warnings."
  type = object({
    critical_repeat_interval = optional(string, "1h")
    group_by                 = optional(list(string), ["grafana_folder", "alertname", "cluster"])
    group_interval           = optional(string, "5m")
    group_wait               = optional(string, "30s")
    warning_repeat_interval  = optional(string, "4h")
  })
}

variable "slack" {
  default     = null
  description = "Slack channel. Set `url` to an incoming webhook URL, or `token` and `recipient` for a bot token and channel. Null disables it."
  sensitive   = true
  type = object({
    mention_channel = optional(string)
    recipient       = optional(string)
    text            = optional(string)
    title           = optional(string)
    token           = optional(string)
    url             = optional(string)
    # Unset, Grafana posts as "Grafana". A bot token needs the
    # chat:write.customize scope to post under another name.
    username = optional(string)
  })

  validation {
    condition     = var.slack == null ? true : (try(var.slack.url, null) != null || (try(var.slack.token, null) != null && try(var.slack.recipient, null) != null))
    error_message = "slack needs either url, or both token and recipient."
  }
}

variable "teams" {
  default     = null
  description = "Microsoft Teams channel. `url` is a Teams Workflows (Power Automate) webhook URL. Null disables it."
  sensitive   = true
  type = object({
    message       = optional(string)
    section_title = optional(string)
    title         = optional(string)
    url           = string
  })
}

variable "title_template" {
  default     = "{{ if eq .Status \"firing\" }}🔴 FIRING{{ if gt (len .Alerts.Firing) 1 }} ({{ len .Alerts.Firing }}){{ end }}{{ else }}✅ RESOLVED{{ if gt (len .Alerts.Resolved) 1 }} ({{ len .Alerts.Resolved }}){{ end }}{{ end }}: {{ .CommonLabels.alertname }}"
  description = "Grafana notification template for the Slack and Teams title and the email subject, unless a channel sets its own. The default starts with 🔴 FIRING or ✅ RESOLVED, then the alert name, so a resolve is easy to match to its alert: Grafana posts it as a new message, not a thread reply."
  nullable    = false
  type        = string
}

variable "webex" {
  default     = null
  description = "Webex channel: a bot token and the room ID to post to. Null disables it."
  sensitive   = true
  type = object({
    api_url = optional(string)
    message = optional(string)
    room_id = string
    token   = string
  })
}
