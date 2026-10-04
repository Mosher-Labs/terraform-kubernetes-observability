locals {
  # Every channel's handle, then the caller's own. The channel resources are
  # referenced so monitors are created after them.
  handles = concat(
    local.email_enabled ? [for a in nonsensitive(var.notifications.email.addresses) : "@${a}"] : [],
    [for c in datadog_integration_slack_channel.this : "@slack-${c.account_name}-${trimprefix(c.channel_name, "#")}"],
    [for t in datadog_integration_ms_teams_workflows_webhook_handle.this : "@teams-${t.name}"],
    [for w in datadog_webhook.webex : "@webhook-${w.name}"],
    var.notification_handles,
  )

  # The notification variables are sensitive. Whether a channel is on, and
  # the names that make up its handle, aren't secret.
  email_enabled = nonsensitive(try(var.notifications.email, null) != null)
  slack_enabled = nonsensitive(try(var.notifications.slack, null) != null)
  teams_enabled = nonsensitive(try(var.notifications.teams, null) != null)
  teams_name    = local.teams_enabled ? coalesce(nonsensitive(var.notifications.teams.name), "kubernetes-${var.cluster_name}") : null

  webex_bot_enabled = local.webex_enabled && !local.webex_webhook_enabled
  webex_enabled     = nonsensitive(try(var.notifications.webex, null) != null)
  # Datadog fills in the variables when it sends: the monitor's name, its
  # rendered message (which starts with 🔴 FIRING or ✅ RESOLVED), and a link
  # to the event. The same markdown as the Grafana backend's Webex messages.
  webex_markdown        = "**$ALERT_TITLE**\n$TEXT_ONLY_MSG\n\n[View in Datadog]($LINK)"
  webex_name            = local.webex_enabled ? coalesce(nonsensitive(var.notifications.webex.name), "kubernetes-${var.cluster_name}") : null
  webex_token_variable  = local.webex_enabled ? "WEBEX_TOKEN_${replace(upper(local.webex_name), "/[^A-Z0-9]/", "_")}" : null
  webex_webhook_enabled = local.webex_enabled && nonsensitive(try(var.notifications.webex.webhook_url, null) != null)
}
