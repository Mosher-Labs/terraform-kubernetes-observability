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

variable "icon_url" {
  default     = null
  description = "URL of an image to show as the sender's avatar, on channels that allow it per message: Slack. Webex and Teams take the avatar from the bot or app that posts; see docs/notifications.md."
  type        = string
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
    icon_url        = optional(string)
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
  default     = "{{ $alerts := .Alerts.Firing }}{{ if eq .Status \"firing\" }}🔴 FIRING{{ else }}{{ $alerts = .Alerts.Resolved }}✅ RESOLVED{{ end }}{{ if gt (len $alerts) 1 }} ({{ len $alerts }}){{ end }}: {{ .CommonLabels.alertname }}{{ range $i, $a := $alerts }}{{ if lt $i 3 }}{{ if $i }}, {{ else }} – {{ end }}{{ $a.Annotations.subject }}{{ end }}{{ end }}{{ if gt (len $alerts) 3 }}, …{{ end }}"
  description = "Grafana notification template for the Slack and Teams title and the email subject, unless a channel sets its own. The default starts with 🔴 FIRING or ✅ RESOLVED, then the alert name and what it is about (the `subject` annotation, such as \"dex-server in argocd\"), listing up to three. Grafana posts a resolve as a new message, not a thread reply, so the title is what pairs them up."
  nullable    = false
  type        = string

  validation {
    condition     = !strcontains(var.title_template, "`")
    error_message = "title_template can't contain backticks: the Webex webhook payload embeds it in a Go raw string."
  }
}

variable "webex" {
  default     = null
  description = "Webex channel. Set `webhook_url` to a Webex incoming webhook URL (no bot needed, so it works where bot creation is blocked), or `token` and `room_id` for a bot. Null disables it."
  sensitive   = true
  type = object({
    api_url     = optional(string)
    message     = optional(string)
    room_id     = optional(string)
    token       = optional(string)
    webhook_url = optional(string)
  })

  validation {
    condition     = var.webex == null ? true : (try(var.webex.webhook_url, null) != null) != (try(var.webex.token, null) != null && try(var.webex.room_id, null) != null)
    error_message = "webex needs either webhook_url, or both token and room_id, but not both."
  }
}
