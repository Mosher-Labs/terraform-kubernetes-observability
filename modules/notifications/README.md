# notifications

Creates one Grafana contact point with any combination of Slack, email, Teams
and Webex, and optionally the notification policy tree.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.5.0 |
| grafana | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| grafana | >= 4.0.0, < 5.0.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [grafana_contact_point.this](https://registry.terraform.io/providers/grafana/grafana/latest/docs/resources/contact_point) | resource |
| [grafana_notification_policy.this](https://registry.terraform.io/providers/grafana/grafana/latest/docs/resources/notification_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| contact\_point\_name | Name of the Grafana contact point that holds every enabled channel. | `string` | n/a | yes |
| email | Email channel. Null disables it. Grafana must have SMTP configured. | ```object({ addresses = list(string) single_email = optional(bool, true) subject = optional(string) message = optional(string) })``` | `null` | no |
| manage\_notification\_policy | Whether to manage the Grafana organization's notification policy tree. Grafana has one tree per organization, so this replaces any policies created elsewhere. Set false to route alerts yourself, using the `cluster` and `severity` labels. | `bool` | `true` | no |
| policy | Grouping and timing for the notification policy. Critical alerts repeat more often than warnings. | ```object({ group_by = optional(list(string), ["grafana_folder", "alertname", "cluster"]) group_wait = optional(string, "30s") group_interval = optional(string, "5m") critical_repeat_interval = optional(string, "1h") warning_repeat_interval = optional(string, "4h") })``` | `{}` | no |
| slack | Slack channel. Set `url` to an incoming webhook URL, or `token` and `recipient` for a bot token and channel. Null disables it. | ```object({ url = optional(string) token = optional(string) recipient = optional(string) # Unset posts under the bot's or webhook's own name. username = optional(string) mention_channel = optional(string) title = optional(string) text = optional(string) })``` | `null` | no |
| teams | Microsoft Teams channel. `url` is a Teams Workflows (Power Automate) webhook URL. Null disables it. | ```object({ url = string title = optional(string) section_title = optional(string) message = optional(string) })``` | `null` | no |
| title\_template | Grafana notification template for the Slack and Teams title and the email subject, unless a channel sets its own. The default starts with 🔴 FIRING or ✅ RESOLVED, then the alert name, so a resolve is easy to match to its alert: Grafana posts it as a new message, not a thread reply. | `string` | `"{{ if eq .Status \"firing\" }}🔴 FIRING{{ if gt (len .Alerts.Firing) 1 }} ({{ len .Alerts.Firing }}){{ end }}{{ else }}✅ RESOLVED{{ if gt (len .Alerts.Resolved) 1 }} ({{ len .Alerts.Resolved }}){{ end }}{{ end }}: {{ .CommonLabels.alertname }}"` | no |
| webex | Webex channel: a bot token and the room ID to post to. Null disables it. | ```object({ token = string room_id = string api_url = optional(string) message = optional(string) })``` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| contact\_point\_name | Name of the contact point, for routing alerts to it from your own notification policy. |
| contact\_point\_title | The title template the contact point uses. |
| enabled\_channels | The notification channels that are turned on. |
<!-- END_TF_DOCS -->
