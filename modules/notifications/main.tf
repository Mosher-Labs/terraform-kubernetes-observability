locals {
  # The channel variables are sensitive, and Terraform refuses to expand a
  # dynamic block over a sensitive collection. Whether a channel is enabled
  # reveals nothing secret, so compute that much outside the mark.
  slack_enabled = nonsensitive(var.slack != null)
  teams_enabled = nonsensitive(var.teams != null)
  webex_enabled = nonsensitive(var.webex != null)
  email_enabled = var.email != null

  any_enabled = local.slack_enabled || local.teams_enabled || local.webex_enabled || local.email_enabled
}

resource "grafana_contact_point" "this" {
  name = var.contact_point_name

  dynamic "email" {
    for_each = local.email_enabled ? [1] : []
    content {
      addresses    = var.email.addresses
      single_email = var.email.single_email
      subject      = coalesce(var.email.subject, var.title_template)
      message      = var.email.message
    }
  }

  dynamic "slack" {
    for_each = local.slack_enabled ? [1] : []
    content {
      url             = var.slack.url
      token           = var.slack.token
      recipient       = var.slack.recipient
      username        = var.slack.username
      mention_channel = var.slack.mention_channel
      title           = coalesce(var.slack.title, var.title_template)
      text            = var.slack.text
    }
  }

  dynamic "teams" {
    for_each = local.teams_enabled ? [1] : []
    content {
      url           = var.teams.url
      title         = coalesce(var.teams.title, var.title_template)
      section_title = var.teams.section_title
      message       = var.teams.message
    }
  }

  dynamic "webex" {
    for_each = local.webex_enabled ? [1] : []
    content {
      token   = var.webex.token
      room_id = var.webex.room_id
      api_url = var.webex.api_url
      message = var.webex.message
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
  group_wait      = var.policy.group_wait
  group_interval  = var.policy.group_interval
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
