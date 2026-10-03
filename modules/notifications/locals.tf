locals {
  any_enabled = local.email_enabled || local.slack_enabled || local.teams_enabled || local.webex_enabled

  email_enabled = var.email != null

  heartbeat_enabled = nonsensitive(var.heartbeat != null)

  # The channel variables are sensitive, and Terraform refuses to expand a
  # dynamic block over a sensitive collection. Whether a channel is enabled
  # reveals nothing secret, so compute that much outside the mark.
  slack_enabled = nonsensitive(var.slack != null)
  teams_enabled = nonsensitive(var.teams != null)

  webex_bot_enabled     = local.webex_enabled && !local.webex_webhook_enabled
  webex_bot_message     = "{{ $title := tmpl.Inline `${var.title_template}` . }}**{{ $title }}**{{ range .Alerts }}\n- {{ .Annotations.summary }}{{ end }}"
  webex_enabled         = nonsensitive(var.webex != null)
  webex_webhook_enabled = local.webex_enabled && nonsensitive(try(var.webex.webhook_url, null) != null)

  # Both Webex modes send the title in bold, then one line per alert. The bot
  # takes it as its message; an incoming webhook takes {"markdown": "..."}. The title reuses var.title_template through
  # tmpl.Inline, which is why that template can't contain backticks.
  webex_webhook_payload = join("", [
    "{{ $title := tmpl.Inline `${var.title_template}` . }}",
    "{{ $body := \"\" }}{{ range .Alerts }}{{ $body = printf \"%s\\n- %s\" $body .Annotations.summary }}{{ end }}",
    "{{ coll.Dict \"markdown\" (printf \"**%s**%s\" $title $body) | data.ToJSON }}",
  ])
}
