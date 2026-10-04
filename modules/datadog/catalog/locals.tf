locals {
  # Every rule this module maps, enabled or not.
  all_rules = merge(local.catalog, local.apm_catalog, local.backing_catalog)

  cluster_scope = "${var.cluster_tag}:${var.cluster_name}"

  comparators = {
    gt = ">"
    lt = "<"
  }

  # What each `requires` value depends on.
  enabled = {
    apiserver = var.control_plane.apiserver
    apm       = var.apm.enabled
    etcd      = var.control_plane.etcd
    mongodb   = var.backing_services.mongodb.enabled
    mysql     = var.backing_services.mysql.enabled
    postgres  = var.backing_services.postgres.enabled
    rabbitmq  = var.backing_services.rabbitmq.enabled
    redis     = var.backing_services.redis.enabled
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

  rules = {
    for id, r in local.all_rules : id => {
      group   = r.group
      metric  = !local.service_check[id]
      paused  = coalesce(try(var.overrides[id].paused, null), false)
      summary = r.summary
      # Metric monitors: the catalog query with its scope and window filled
      # in, then the comparison against the threshold. Service checks: the
      # status count over the last threshold + 1 runs.
      query = local.service_check[id] ? replace(replace(r.query,
        "__TAGS__", "\"${local.cluster_scope}\""),
        "__LAST__", tostring(local.thresholds[id] + 1),
        ) : format("%s %s %s",
        replace(replace(r.query,
          "__SCOPE__", local.scopes[id]),
          "__WINDOW__", local.windows[id],
        ),
        local.comparators[r.operator],
        local.thresholds[id],
      )
      require_full_window = try(r.require_full_window, true)
      severity            = coalesce(try(var.overrides[id].severity, null), r.severity)
      threshold           = local.thresholds[id]
      title               = "[${var.cluster_name}] ${r.title}"
      type                = try(r.type, "query alert")
      window              = local.service_check[id] ? null : local.windows[id]
      on_missing_data     = local.service_check[id] ? null : try(r.on_missing_data, "default")
    }
    if !contains(var.disabled_rules, id) && (try(r.requires, null) == null ? true : local.enabled[r.requires])
  }

  # Workload rules add var.workload_scope and backing-service rules add
  # var.backing_services.scope to the cluster tag.
  scopes = {
    for id, r in local.all_rules : id => (
      try(r.workload, false) && var.workload_scope != "" ? "${local.cluster_scope} AND ${var.workload_scope}" :
      try(r.backing, false) && var.backing_services.scope != "" ? "${local.cluster_scope} AND ${var.backing_services.scope}" :
      local.cluster_scope
    )
  }

  service_check = { for id, r in local.all_rules : id => try(r.type, "") == "service check" }

  thresholds = { for id, r in local.all_rules : id => coalesce(try(var.overrides[id].threshold, null), r.threshold) }

  unknown_ids = setsubtract(setunion(var.disabled_rules, keys(var.overrides)), keys(local.all_rules))

  windows = { for id, r in local.all_rules : id => try(var.overrides[id].window, null) != null ? var.overrides[id].window : try(r.window, null) }
}
