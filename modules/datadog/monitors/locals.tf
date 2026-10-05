locals {
  cluster_scope = "${var.cluster_tag}:${var.cluster_name}"

  comparators = {
    gt = ">"
    lt = "<"
  }

  # The first line of every notification, matching the Grafana backend's
  # titles. Datadog fills in the section that matches the monitor's state.
  # Search for "is_no_data" in Datadog's monitor variables docs.
  message_prefix = "{{#is_alert}}🔴 FIRING{{/is_alert}}{{#is_no_data}}🔴 FIRING (no data){{/is_no_data}}{{#is_recovery}}✅ RESOLVED{{/is_recovery}}"

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

  # The catalog's rules, with what the monitor resource needs. A service
  # check's query is complete, and a metric monitor's gets its comparison.
  rules = {
    for id, r in module.catalog.rules : id => {
      group  = r.group
      metric = !local.service_check[id]
      paused = r.paused
      query = local.service_check[id] ? r.query : format("%s %s %s",
        local.zero_filled[id] ? format("%sdefault_zero(%s)", local.query_parts[id][0], local.query_parts[id][1]) : join("", local.query_parts[id]),
        local.comparators[r.operator],
        r.threshold,
      )
      require_full_window = try(r.require_full_window, true)
      severity            = r.severity
      summary             = r.summary
      threshold           = r.threshold
      title               = "[${var.cluster_name}] ${r.title}"
      type                = try(r.type, "query alert")
      window              = local.service_check[id] ? null : try(r.window, null)
      on_missing_data     = local.service_check[id] ? null : try(r.on_missing_data, "default")
    }
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
