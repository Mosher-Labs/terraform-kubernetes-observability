resource "grafana_contact_point" "this" {
  name = var.contact_point_name

  dynamic "email" {
    for_each = local.email_enabled ? [1] : []
    content {
      addresses    = var.email.addresses
      message      = var.email.message
      single_email = var.email.single_email
      subject      = coalesce(var.email.subject, var.title_template)
    }
  }

  dynamic "slack" {
    for_each = local.slack_enabled ? [1] : []
    content {
      icon_url        = try(coalesce(var.slack.icon_url, var.icon_url), null)
      mention_channel = var.slack.mention_channel
      recipient       = var.slack.recipient
      text            = var.slack.text
      title           = coalesce(var.slack.title, var.title_template)
      token           = var.slack.token
      url             = var.slack.url
      username        = var.slack.username
    }
  }

  dynamic "teams" {
    for_each = local.teams_enabled ? [1] : []
    content {
      message       = var.teams.message
      section_title = var.teams.section_title
      title         = coalesce(var.teams.title, var.title_template)
      url           = var.teams.url
    }
  }

  dynamic "webex" {
    for_each = local.webex_bot_enabled ? [1] : []
    content {
      api_url = var.webex.api_url
      message = var.webex.message
      room_id = var.webex.room_id
      token   = var.webex.token
    }
  }

  # Webex incoming webhooks go through Grafana's generic webhook integration
  # with a Webex-shaped payload.
  dynamic "webhook" {
    for_each = local.webex_webhook_enabled ? [1] : []
    content {
      http_method = "POST"
      url         = var.webex.webhook_url

      payload {
        template = local.webex_webhook_payload
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.any_enabled
      error_message = "Enable at least one notification channel: slack, email, teams or webex."
    }
  }
}

resource "grafana_notification_policy" "this" {
  count = var.manage_notification_policy ? 1 : 0

  contact_point   = grafana_contact_point.this.name
  group_by        = var.policy.group_by
  group_interval  = var.policy.group_interval
  group_wait      = var.policy.group_wait
  repeat_interval = var.policy.warning_repeat_interval

  policy {
    contact_point   = grafana_contact_point.this.name
    group_by        = var.policy.group_by
    repeat_interval = var.policy.critical_repeat_interval

    matcher {
      label = "severity"
      match = "="
      value = "critical"
    }
  }

  policy {
    contact_point   = grafana_contact_point.this.name
    group_by        = var.policy.group_by
    repeat_interval = var.policy.warning_repeat_interval

    matcher {
      label = "severity"
      match = "="
      value = "warning"
    }
  }
}
