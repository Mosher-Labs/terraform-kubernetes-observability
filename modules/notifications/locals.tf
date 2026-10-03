locals {
  any_enabled = local.email_enabled || local.slack_enabled || local.teams_enabled || local.webex_enabled

  email_enabled = var.email != null

  heartbeat_enabled = nonsensitive(var.heartbeat != null)

  # The channel variables are sensitive, and Terraform refuses to expand a
  # dynamic block over a sensitive collection. Whether a channel is enabled
  # reveals nothing secret, so compute that much outside the mark.
  slack_enabled = nonsensitive(var.slack != null)

  # Teams with an icon gets a custom Adaptive Card through the webhook
  # integration: the icon and the title, red when firing and green when
  # resolved, then one line per alert and a link to Grafana.
  teams_card_enabled = local.teams_enabled && local.teams_icon_url != null
  teams_card_payload = join("", [
    "{{ $title := tmpl.Inline `${var.title_template}` . }}",
    "{{ $body := \"\" }}{{ range .Alerts }}{{ $body = printf \"%s- %s\\n\" $body .Annotations.summary }}{{ end }}",
    "{{ $color := \"Good\" }}{{ if eq .Status \"firing\" }}{{ $color = \"Attention\" }}{{ end }}",
    # One alert links to its rule; several link to the alert list.
    "{{ $link := printf \"%salerting/list\" .ExternalURL }}{{ if eq (len .Alerts) 1 }}{{ with (index .Alerts 0).GeneratorURL }}{{ $link = . }}{{ end }}{{ end }}",
    "{{ $icon := coll.Dict \"type\" \"Image\" \"url\" .Vars.icon_url \"size\" \"Small\" \"style\" \"Person\" }}",
    "{{ $head := coll.Dict \"type\" \"TextBlock\" \"text\" $title \"weight\" \"Bolder\" \"size\" \"Medium\" \"wrap\" true \"color\" $color }}",
    "{{ $columns := coll.Slice (coll.Dict \"type\" \"Column\" \"width\" \"auto\" \"items\" (coll.Slice $icon)) (coll.Dict \"type\" \"Column\" \"width\" \"stretch\" \"verticalContentAlignment\" \"Center\" \"items\" (coll.Slice $head)) }}",
    "{{ $card := coll.Dict \"$schema\" \"http://adaptivecards.io/schemas/adaptive-card.json\" \"type\" \"AdaptiveCard\" \"version\" \"1.4\" \"msteams\" (coll.Dict \"width\" \"Full\") \"body\" (coll.Slice (coll.Dict \"type\" \"ColumnSet\" \"columns\" $columns) (coll.Dict \"type\" \"TextBlock\" \"text\" $body \"wrap\" true)) \"actions\" (coll.Slice (coll.Dict \"type\" \"Action.OpenUrl\" \"title\" \"View in Grafana\" \"url\" $link)) }}",
    "{{ coll.Dict \"type\" \"message\" \"summary\" $title \"attachments\" (coll.Slice (coll.Dict \"contentType\" \"application/vnd.microsoft.card.adaptive\" \"content\" $card)) | data.ToJSON }}",
  ])
  teams_enabled  = nonsensitive(var.teams != null)
  teams_icon_url = local.teams_enabled ? try(coalesce(nonsensitive(var.teams.icon_url), var.icon_url), null) : null

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
