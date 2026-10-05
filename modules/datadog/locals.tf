locals {
  cluster_scope = "${var.cluster_tag}:${var.cluster_name}"

  comparators = {
    gt = ">"
    lt = "<"
  }

  # Every channel's handle, then the caller's own. The channel resources are
  # referenced so monitors are created after them.
  handles = concat(
    local.email_enabled ? [for a in nonsensitive(var.notifications.email.addresses) : "@${a}"] : [],
    [for c in datadog_integration_slack_channel.this : "@slack-${c.account_name}-${trimprefix(c.channel_name, "#")}"],
    [for t in datadog_integration_ms_teams_workflows_webhook_handle.this : "@teams-${t.name}"],
    # An incoming Webex webhook takes every monitor, with the graph link
    # (empty for service checks).
    local.webex_webhook_enabled ? [for w in datadog_webhook.webex : "@webhook-${w.name}"] : [],
    var.notification_handles,
  )

  # In bot mode, metric monitors go to the webhook that links the graph, and
  # service checks (which have no graph) to the text-only one.
  metric_handles        = local.webex_bot_enabled ? [for w in datadog_webhook.webex : "@webhook-${w.name}"] : []
  service_check_handles = [for w in datadog_webhook.webex_text : "@webhook-${w.name}"]

  # The notification variables are sensitive. Whether a channel is on, and
  # the names that make up its handle, aren't secret.
  email_enabled = nonsensitive(try(var.notifications.email, null) != null)
  slack_enabled = nonsensitive(try(var.notifications.slack, null) != null)
  teams_enabled = nonsensitive(try(var.notifications.teams, null) != null)
  teams_name    = local.teams_enabled ? coalesce(nonsensitive(var.notifications.teams.name), "kubernetes-${var.cluster_name}") : null

  webex_bot_enabled = local.webex_enabled && !local.webex_webhook_enabled
  webex_enabled     = nonsensitive(try(var.notifications.webex, null) != null)
  # Datadog fills in the variables when it sends: the monitor's name, and its
  # rendered message, which starts with 🔴 FIRING or ✅ RESOLVED. $EVENT_MSG
  # keeps Datadog's markdown links ([Monitor Status](...)); $TEXT_ONLY_MSG
  # turned them into long raw URLs.
  webex_markdown = "**$ALERT_TITLE**\n\n$EVENT_MSG"
  # Metric monitors also link their graph. Webex can't show images inline, and
  # attaching $SNAPSHOT fails: Datadog renders the image a few seconds after
  # sending, so Webex downloads an empty file. By the time someone clicks the
  # link, the image is there.
  webex_graph_markdown  = "${local.webex_markdown}\n\n[📈 View graph]($SNAPSHOT)"
  webex_name            = local.webex_enabled ? coalesce(nonsensitive(var.notifications.webex.name), "kubernetes-${var.cluster_name}") : null
  webex_token_variable  = local.webex_enabled ? "WEBEX_TOKEN_${replace(upper(local.webex_name), "/[^A-Z0-9]/", "_")}" : null
  webex_webhook_enabled = local.webex_enabled && nonsensitive(try(var.notifications.webex.webhook_url, null) != null)

  # The first line of every notification, matching the Grafana backend's
  # titles. Datadog fills in the section that matches the monitor's state.
  # Search for "is_no_data" in Datadog's monitor variables docs.
  message_prefix = "{{#is_alert}}🔴 FIRING{{/is_alert}}{{#is_no_data}}🔴 FIRING (no data){{/is_no_data}}{{#is_recovery}}✅ RESOLVED{{/is_recovery}}"

  # Every monitor argument, keyed by rule ID. The catalog gives each rule's
  # query without its comparison (a service check's query is complete).
  monitors = {
    for id, r in module.catalog.rules : id => {
      draft_status = r.paused ? "draft" : "published"
      group        = r.group
      message      = trimspace("${local.message_prefix}\n${r.summary}\n\n${join(" ", concat(local.handles, local.service_check[id] ? local.service_check_handles : local.metric_handles))}")
      name         = "[${var.cluster_name}] ${r.title}"
      # Datadog's defaults apply when a rule doesn't set these. Service checks
      # take neither.
      on_missing_data = local.service_check[id] ? null : try(r.on_missing_data, "default")
      priority        = local.priorities[r.severity]
      # Metric monitors: the query with the comparison against the threshold
      # added. Service checks: the query as it is.
      query = local.service_check[id] ? r.query : format("%s %s %s",
        local.zero_filled[id] ? format("%sdefault_zero(%s)", local.query_parts[id][0], local.query_parts[id][1]) : join("", local.query_parts[id]),
        local.comparators[r.operator],
        r.threshold,
      )
      renotify_interval   = var.renotify_interval_minutes[r.severity]
      require_full_window = local.service_check[id] ? null : try(r.require_full_window, true)
      severity            = r.severity
      tags                = concat(var.tags, ["cluster:${var.cluster_name}", "group:${r.group}", "rule_id:${id}", "severity:${r.severity}"])
      threshold           = r.threshold
      type                = try(r.type, "query alert")
      window              = local.service_check[id] ? null : try(r.window, null)
    }
  }

  # Datadog priority, 1 (high) to 5 (low).
  priorities = {
    critical = 1
    info     = 5
    warning  = 3
  }

  # Each metric query split into its time aggregation ("min(last_10m):") and
  # the expression after it.
  query_parts = {
    for id, r in module.catalog.rules : id => regex("^([a-z0-9_]+\\([a-z0-9_]+\\):)(.*)$", r.query) if !local.service_check[id]
  }

  service_check = { for id, r in module.catalog.rules : id => try(r.type, "") == "service check" }

  unknown_ids = setsubtract(setunion(var.disabled_rules, keys(var.overrides)), module.catalog.known_rule_ids)

  # A multi-alert group whose object is deleted (a Deployment, a pod, a PVC)
  # stops reporting, and Datadog keeps the group in its last state, so an
  # alert would never resolve. default_zero() turns the gap into 0, which
  # resolves rules that alert above a threshold. Rules that alert below one
  # (no leader, expiring certificates, traffic drop, cluster not reporting)
  # would fire on a 0, so they keep their gaps.
  zero_filled = {
    for id, r in module.catalog.rules : id => r.operator == "gt" && try(r.default_zero, true) && !startswith(local.query_parts[id][1], "default_zero(") if !local.service_check[id]
  }
}
