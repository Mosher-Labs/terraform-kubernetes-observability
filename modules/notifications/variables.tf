variable "contact_point_name" {
  description = "Name of the Grafana contact point that holds every enabled channel."
  type        = string
}

variable "email" {
  description = "Email channel. Null disables it. Grafana must have SMTP configured."
  type = object({
    addresses    = list(string)
    single_email = optional(bool, true)
    subject      = optional(string)
    message      = optional(string)
  })
  default = null
}

variable "manage_notification_policy" {
  description = "Whether to manage the Grafana organization's notification policy tree. Grafana has one tree per organization, so this replaces any policies created elsewhere. Set false to route alerts yourself, using the `cluster` and `severity` labels."
  type        = bool
  default     = true
}

variable "policy" {
  description = "Grouping and timing for the notification policy. Critical alerts repeat more often than warnings."
  type = object({
    group_by                 = optional(list(string), ["grafana_folder", "alertname", "cluster"])
    group_wait               = optional(string, "30s")
    group_interval           = optional(string, "5m")
    critical_repeat_interval = optional(string, "1h")
    warning_repeat_interval  = optional(string, "4h")
  })
  default = {}
}

variable "slack" {
  description = "Slack channel. Set `url` to an incoming webhook URL, or `token` and `recipient` for a bot token and channel. Null disables it."
  type = object({
    url       = optional(string)
    token     = optional(string)
    recipient = optional(string)
    # Unset posts under the bot's or webhook's own name.
    username        = optional(string)
    mention_channel = optional(string)
    title           = optional(string)
    text            = optional(string)
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.slack == null ? true : (try(var.slack.url, null) != null || (try(var.slack.token, null) != null && try(var.slack.recipient, null) != null))
    error_message = "slack needs either url, or both token and recipient."
  }
}

variable "title_template" {
  description = "Grafana notification template for the Slack and Teams title and the email subject, unless a channel sets its own. The default starts with 🔴 FIRING or ✅ RESOLVED, then the alert name, so a resolve is easy to match to its alert: Grafana posts it as a new message, not a thread reply."
  type        = string
  nullable    = false
  default     = "{{ if eq .Status \"firing\" }}🔴 FIRING{{ if gt (len .Alerts.Firing) 1 }} ({{ len .Alerts.Firing }}){{ end }}{{ else }}✅ RESOLVED{{ if gt (len .Alerts.Resolved) 1 }} ({{ len .Alerts.Resolved }}){{ end }}{{ end }}: {{ .CommonLabels.alertname }}"
}

variable "teams" {
  description = "Microsoft Teams channel. `url` is a Teams Workflows (Power Automate) webhook URL. Null disables it."
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
  description = "Webex channel: a bot token and the room ID to post to. Null disables it."
  type = object({
    token   = string
    room_id = string
    api_url = optional(string)
    message = optional(string)
  })
  default   = null
  sensitive = true
}
