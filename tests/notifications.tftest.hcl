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
    webex              = { token = "webex-test", room_id = "room-1" }
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
