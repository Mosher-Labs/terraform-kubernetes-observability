# Run from modules/datadog: terraform init -backend=false && terraform test.
# The root tests cover the catalog; this checks the monitor resource mapping.
mock_provider "datadog" {}

run "monitors_map_the_catalog" {
  command = plan

  variables {
    cluster_name         = "homelab"
    notification_handles = ["@slack-homelab"]
    overrides            = { pod_pending = { paused = true } }
  }

  assert {
    condition     = length(datadog_monitor.this) == 36
    error_message = "Expected one monitor per catalog rule."
  }

  assert {
    condition     = datadog_monitor.this["pod_crash_looping"].monitor_thresholds[0].critical == "5" && endswith(datadog_monitor.this["pod_crash_looping"].query, "> 5")
    error_message = "The critical threshold must match the threshold in the query."
  }

  assert {
    condition     = datadog_monitor.this["node_not_ready"].priority == "1" && datadog_monitor.this["node_not_ready"].type == "query alert"
    error_message = "Critical rules should be priority 1 query alerts."
  }

  assert {
    condition     = datadog_monitor.this["pod_pending"].draft_status == "draft"
    error_message = "A paused rule should be a draft monitor."
  }

  assert {
    condition     = endswith(datadog_monitor.this["pod_pending"].message, "@slack-homelab")
    error_message = "Monitors should notify the handles."
  }
}

run "service_checks_recover_after_one_success" {
  command = plan

  variables {
    cluster_name = "homelab"
  }

  assert {
    condition     = datadog_monitor.this["scrape_target_down"].type == "service check" && datadog_monitor.this["scrape_target_down"].monitor_thresholds[0].ok == "1" && datadog_monitor.this["scrape_target_down"].monitor_thresholds[0].critical == "40"
    error_message = "Service checks should alert after the threshold's failed runs and recover after one success."
  }
}

run "every_channel_becomes_a_handle" {
  command = plan

  variables {
    cluster_name         = "homelab"
    notification_handles = ["@pagerduty-oncall"]
    notifications = {
      email = { addresses = ["oncall@example.com"] }
      slack = { account_name = "mosher-labs", channel = "homelab" }
      teams = { url = "https://example.invalid/teams" }
      webex = { webhook_url = "https://webexapis.com/v1/webhooks/incoming/example" }
    }
  }

  assert {
    condition     = datadog_integration_slack_channel.this[0].channel_name == "#homelab" && datadog_integration_slack_channel.this[0].account_name == "mosher-labs"
    error_message = "The Slack channel should be created with a # prefix in the configured workspace."
  }

  assert {
    condition     = datadog_integration_ms_teams_workflows_webhook_handle.this[0].name == "kubernetes-homelab"
    error_message = "The Teams handle should default to kubernetes-<cluster_name>."
  }

  assert {
    condition     = datadog_webhook.webex[0].name == "kubernetes-homelab" && jsondecode(datadog_webhook.webex[0].payload).markdown == "**$ALERT_TITLE**\n$TEXT_ONLY_MSG\n\n[View in Datadog]($LINK)" && datadog_webhook.webex[0].custom_headers == null
    error_message = "Webex webhook mode should post {\"markdown\": ...} with no extra headers."
  }

  assert {
    condition     = length(datadog_webhook_custom_variable.webex_token) == 0
    error_message = "Webhook mode needs no bot token variable."
  }

  assert {
    condition     = endswith(nonsensitive(datadog_monitor.this["pod_pending"].message), "@oncall@example.com @slack-mosher-labs-homelab @teams-kubernetes-homelab @webhook-kubernetes-homelab @pagerduty-oncall")
    error_message = "Monitors should notify every channel's handle, then the extra handles."
  }
}

run "webex_bot_posts_with_a_secret_token" {
  command = plan

  variables {
    cluster_name = "homelab"
    notifications = {
      webex = { name = "heimdallr", room_id = "room-123", token = "not-a-real-token" }
    }
  }

  assert {
    condition     = datadog_webhook.webex[0].url == "https://webexapis.com/v1/messages" && jsondecode(datadog_webhook.webex[0].payload).roomId == "room-123"
    error_message = "Bot mode should post to the Webex messages API with the room ID."
  }

  assert {
    condition     = datadog_webhook.webex[0].custom_headers == jsonencode({ Authorization = "Bearer $WEBEX_TOKEN_HEIMDALLR" }) && datadog_webhook_custom_variable.webex_token[0].name == "WEBEX_TOKEN_HEIMDALLR" && datadog_webhook_custom_variable.webex_token[0].is_secret
    error_message = "The bot token should be a secret custom variable that the Authorization header references."
  }

  assert {
    condition     = endswith(nonsensitive(datadog_monitor.this["pod_pending"].message), "@webhook-heimdallr")
    error_message = "Monitors should notify the Webex webhook handle."
  }
}

run "webex_needs_one_mode" {
  command = plan

  variables {
    cluster_name = "homelab"
    notifications = {
      webex = { room_id = "room-123", token = "not-a-real-token", webhook_url = "https://example.invalid/hook" }
    }
  }

  expect_failures = [var.notifications]
}
