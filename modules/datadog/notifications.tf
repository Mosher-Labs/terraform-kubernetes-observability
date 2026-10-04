resource "datadog_integration_ms_teams_workflows_webhook_handle" "this" {
  count = local.teams_enabled ? 1 : 0

  name = local.teams_name
  url  = var.notifications.teams.url
}

resource "datadog_integration_slack_channel" "this" {
  count = local.slack_enabled ? 1 : 0

  account_name = nonsensitive(var.notifications.slack.account_name)
  channel_name = "#${trimprefix(nonsensitive(var.notifications.slack.channel), "#")}"

  display {
    message  = true
    notified = true
    snapshot = true
    tags     = true
  }
}

# An incoming webhook takes {"markdown": "..."}. A bot posts to the messages
# API with its token, kept in a secret custom variable so it isn't shown in
# Datadog's webhook settings.
resource "datadog_webhook" "webex" {
  count = local.webex_enabled ? 1 : 0

  custom_headers = local.webex_bot_enabled ? jsonencode({ Authorization = format("Bearer $%s", local.webex_token_variable) }) : null
  encode_as      = "json"
  name           = local.webex_name
  payload = local.webex_bot_enabled ? jsonencode({
    markdown = local.webex_markdown
    roomId   = var.notifications.webex.room_id
  }) : jsonencode({ markdown = local.webex_markdown })
  url = local.webex_bot_enabled ? var.notifications.webex.api_url : var.notifications.webex.webhook_url

  depends_on = [datadog_webhook_custom_variable.webex_token]
}

resource "datadog_webhook_custom_variable" "webex_token" {
  count = local.webex_bot_enabled ? 1 : 0

  is_secret = true
  name      = local.webex_token_variable
  value     = var.notifications.webex.token
}
