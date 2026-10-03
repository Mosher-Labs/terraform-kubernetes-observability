mock_provider "grafana" {}

run "requires_a_channel" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
  }

  expect_failures = [grafana_contact_point.this]
}

run "slack_and_email" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    slack              = { url = "https://hooks.slack.com/services/T000/B000/XXXX" }
    email              = { addresses = ["oncall@example.com"] }
  }

  assert {
    condition     = output.enabled_channels == tolist(["email", "slack"])
    error_message = "Only email and slack should be enabled."
  }

  assert {
    condition     = length(grafana_contact_point.this.slack) == 1 && length(grafana_contact_point.this.email) == 1 && length(grafana_contact_point.this.teams) == 0 && length(grafana_contact_point.this.webex) == 0
    error_message = "The contact point should have exactly one slack and one email integration."
  }

  assert {
    condition     = length(grafana_notification_policy.this) == 1
    error_message = "The notification policy should be managed by default."
  }
}

run "all_four_channels" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    slack              = { token = "xoxb-test", recipient = "#alerts" }
    email              = { addresses = ["oncall@example.com"] }
    teams              = { url = "https://example.webhook.office.com/workflows/test" }
    webex              = { room_id = "room-1", token = "webex-test" }
  }

  assert {
    condition     = output.enabled_channels == tolist(["email", "slack", "teams", "webex"])
    error_message = "All four channels should be enabled."
  }
}

run "slack_needs_url_or_token_and_recipient" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    slack              = { token = "xoxb-test" }
  }

  expect_failures = [var.slack]
}

run "policy_can_be_left_alone" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name         = "kubernetes-homelab"
    email                      = { addresses = ["oncall@example.com"] }
    manage_notification_policy = false
  }

  assert {
    condition     = length(grafana_notification_policy.this) == 0
    error_message = "manage_notification_policy = false should leave the policy tree alone."
  }
}

run "default_title_marks_firing_and_resolved" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    slack              = { url = "https://hooks.slack.com/services/T000/B000/XXXX" }
    email              = { addresses = ["oncall@example.com"] }
  }

  assert {
    condition     = nonsensitive(strcontains(one(grafana_contact_point.this.slack).title, "🔴 FIRING") && strcontains(one(grafana_contact_point.this.slack).title, "✅ RESOLVED"))
    error_message = "Slack should get the default title template."
  }

  assert {
    condition     = nonsensitive(strcontains(one(grafana_contact_point.this.slack).title, "Annotations.subject"))
    error_message = "The default title should name what each alert is about."
  }

  assert {
    condition     = strcontains(one(grafana_contact_point.this.email).subject, "✅ RESOLVED")
    error_message = "The email subject should default to the title template."
  }

  assert {
    condition     = nonsensitive(one(grafana_contact_point.this.slack).username == null)
    error_message = "username should stay unset unless the caller sets it."
  }
}

run "channel_title_overrides_template" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    slack              = { url = "https://hooks.slack.com/services/T000/B000/XXXX", title = "custom" }
  }

  assert {
    condition     = nonsensitive(one(grafana_contact_point.this.slack).title == "custom")
    error_message = "A channel's own title should win over the template."
  }
}

run "webex_incoming_webhook_needs_no_bot" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    webex              = { webhook_url = "https://webexapis.com/v1/webhooks/incoming/test" }
  }

  assert {
    condition     = length(grafana_contact_point.this.webex) == 0 && length(grafana_contact_point.this.webhook) == 1
    error_message = "A Webex webhook URL should use Grafana's webhook integration, not the bot integration."
  }

  assert {
    condition     = strcontains(nonsensitive(one(one(grafana_contact_point.this.webhook).payload).template), "coll.Dict \"markdown\"")
    error_message = "The payload should be Webex's {\"markdown\": ...} shape."
  }

  assert {
    condition     = output.enabled_channels == tolist(["webex"])
    error_message = "Webex should count as an enabled channel."
  }
}

run "webex_needs_exactly_one_mode" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    webex              = { room_id = "room-1", token = "t", webhook_url = "https://webexapis.com/v1/webhooks/incoming/test" }
  }

  expect_failures = [var.webex]
}

run "title_template_rejects_backticks" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    email              = { addresses = ["oncall@example.com"] }
    title_template     = "`raw`"
  }

  expect_failures = [var.title_template]
}

run "icon_url_applies_to_slack" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    icon_url           = "https://example.com/logo.png"
    slack              = { recipient = "C0123456789", token = "xoxb-test" }
  }

  assert {
    condition     = nonsensitive(one(grafana_contact_point.this.slack).icon_url == "https://example.com/logo.png")
    error_message = "The shared icon_url should become Slack's icon."
  }
}

run "slack_icon_url_wins" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    icon_url           = "https://example.com/logo.png"
    slack              = { icon_url = "https://example.com/slack.png", url = "https://hooks.slack.com/services/T000/B000/XXXX" }
  }

  assert {
    condition     = nonsensitive(one(grafana_contact_point.this.slack).icon_url == "https://example.com/slack.png")
    error_message = "A channel's own icon_url should win over the shared one."
  }
}

run "webex_bot_gets_the_title_and_summaries" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    webex              = { room_id = "room-1", token = "t" }
  }

  assert {
    condition     = strcontains(nonsensitive(one(grafana_contact_point.this.webex).message), "tmpl.Inline") && strcontains(nonsensitive(one(grafana_contact_point.this.webex).message), ".Annotations.summary")
    error_message = "The Webex bot should get the title template and one line per alert, like the webhook mode."
  }
}

run "heartbeat_has_its_own_contact_point_and_route" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    heartbeat          = { url = "https://hc-ping.com/00000000-0000-0000-0000-000000000000" }
    slack              = { url = "https://hooks.slack.com/services/T000/B000/XXXX" }
  }

  assert {
    condition     = grafana_contact_point.heartbeat[0].name == "kubernetes-homelab-heartbeat"
    error_message = "The heartbeat should get its own contact point."
  }

  assert {
    condition     = grafana_notification_policy.this[0].policy[0].contact_point == "kubernetes-homelab-heartbeat" && grafana_notification_policy.this[0].policy[0].repeat_interval == "5m"
    error_message = "The first policy should send the heartbeat to its contact point every interval."
  }

  assert {
    condition     = one(grafana_notification_policy.this[0].policy[0].matcher).label == "heartbeat"
    error_message = "The heartbeat route should match the heartbeat label."
  }
}

run "heartbeat_needs_the_policy" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name         = "kubernetes-homelab"
    heartbeat                  = { url = "https://hc-ping.com/00000000-0000-0000-0000-000000000000" }
    manage_notification_policy = false
    slack                      = { url = "https://hooks.slack.com/services/T000/B000/XXXX" }
  }

  expect_failures = [grafana_contact_point.heartbeat]
}

run "teams_without_an_icon_uses_the_built_in_card" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    teams              = { url = "https://example.environment.api.powerplatform.com/workflows/test" }
  }

  assert {
    condition     = length(grafana_contact_point.this.teams) == 1 && length(grafana_contact_point.this.webhook) == 0
    error_message = "Without an icon, Teams should use Grafana's built-in Teams integration."
  }
}

run "teams_with_an_icon_gets_a_custom_card" {
  command = plan

  module {
    source = "./modules/notifications"
  }

  variables {
    contact_point_name = "kubernetes-homelab"
    icon_url           = "https://example.com/logo.png"
    teams              = { url = "https://example.environment.api.powerplatform.com/workflows/test" }
  }

  assert {
    condition     = length(grafana_contact_point.this.teams) == 0 && length(grafana_contact_point.this.webhook) == 1
    error_message = "With an icon, Teams should use the webhook integration with a custom card."
  }

  assert {
    condition     = strcontains(nonsensitive(one(one(grafana_contact_point.this.webhook).payload).template), "application/vnd.microsoft.card.adaptive") && nonsensitive(one(one(grafana_contact_point.this.webhook).payload).vars.icon_url) == "https://example.com/logo.png"
    error_message = "The card should be an Adaptive Card carrying the icon URL."
  }
}
