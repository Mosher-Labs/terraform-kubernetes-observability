locals {
  all_rules = merge(local.core_rules, local.apm_rules, local.backing_rules)

  backends = ["datadog", "grafana"]

  # Backend-specific fields a rule must carry for each backend, unless the
  # backend's block says `skip`.
  backend_fields = {
    datadog = ["query", "summary"]
    grafana = ["expr", "pending_period", "subject", "summary"]
  }

  # Fields every rule defines once, at the top level.
  required_shared_fields = ["group", "operator", "severity", "threshold", "title"]

  # Fields a backend block may override. Each override is listed in
  # backend_overrides, and the tests pin the list.
  shared_fields = concat(local.required_shared_fields, ["requires", "workload"])

  # Rules that miss a shared field, or have neither a block nor a skip reason
  # for a backend.
  coverage_gaps = {
    for b in local.backends : b => sort([
      for id, r in local.all_rules : id
      if try(length(r[b].skip) > 0, false) ? false : !alltrue([for f in local.backend_fields[b] : can(r[b][f])])
    ])
  }
  incomplete_rules = sort([
    for id, r in local.all_rules : id if !alltrue([for f in local.required_shared_fields : can(r[f])])
  ])
  uncovered_ids = setunion(local.incomplete_rules, local.coverage_gaps.datadog, local.coverage_gaps.grafana)

  # What turns each `requires` value on.
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

  # The shared fields, then the chosen backend's block on top of them. A field
  # in the block replaces the shared one.
  backend_rules = {
    for id, r in local.all_rules : id => merge(
      { for k, v in r : k => v if !contains(local.backends, k) },
      { for k, v in r[var.catalog] : k => v if k != "skip" },
    ) if !contains(local.uncovered_ids, id) && try(r[var.catalog].skip, null) == null
  }

  skipped_rules = {
    for id, r in local.all_rules : id => r[var.catalog].skip
    if !contains(local.uncovered_ids, id) && try(r[var.catalog].skip, null) != null
  }

  # Which shared fields each backend's block replaces, for the rules that do.
  override_lists = {
    for id, r in local.all_rules : id => {
      for b in local.backends : b => sort([for k in keys(try(r[b], {})) : k if contains(local.shared_fields, k)])
    }
  }
  backend_overrides = {
    for id, lists in local.override_lists : id => { for b, fields in lists : b => fields if length(fields) > 0 }
    if length(flatten(values(lists))) > 0
  }

  # The datadog filter for each rule: the cluster, plus the workload scope on
  # workload rules or the backing-service scope on backing-service rules.
  datadog_scope = {
    for id, r in local.backend_rules : id => (
      try(r.workload, false) && var.workload_scope != "" ? "${var.cluster_scope} AND ${var.workload_scope}" :
      r.group == "backing-services" && var.backing_services.scope != "" ? "${var.cluster_scope} AND ${var.backing_services.scope}" :
      var.cluster_scope
    )
  }

  # Values after the caller's overrides. The time field depends on the
  # backend: grafana's pending period, or datadog's evaluation window.
  with_overrides = {
    for id, r in local.backend_rules : id => merge(
      r,
      {
        paused    = coalesce(try(var.overrides[id].paused, null), false)
        severity  = coalesce(try(var.overrides[id].severity, null), r.severity)
        threshold = coalesce(try(var.overrides[id].threshold, null), r.threshold)
      },
      {
        for k, v in {
          pending_period = try(var.overrides[id].pending_period, null) != null ? var.overrides[id].pending_period : try(r.pending_period, null)
          window         = try(var.overrides[id].window, null) != null ? var.overrides[id].window : try(r.window, null)
        } : k => v if k == (var.catalog == "grafana" ? "pending_period" : "window")
      },
    )
  }

  # The rules turned on, with every placeholder in their text filled in:
  #   __M__, __S__, __R__, __C__, __FLOOR__, __SPAN__  from var.apm
  #   __ASEL__, __APM__                                 var.apm.scope
  #   __BSEL__                                          var.backing_services.scope
  #   __SEL__                                           var.workload_scope
  #   __SCOPE__, __TAGS__                               var.cluster_scope and the scopes above
  #   __WINDOW__, __LAST__                              the window and threshold after overrides
  # The _SEL_ forms drop out cleanly when the scope is empty: `{__SEL__}`
  # becomes nothing and `,__SEL__}` becomes `}`.
  rules = {
    for id, r in local.with_overrides : id => merge(r, {
      for field in ["expr", "query", "subject", "summary"] : field => replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(r[field],
        "__M__", var.apm.metric),
        "__S__", var.apm.service_label),
        "__R__", var.apm.route_label),
        "__C__", var.apm.status_label),
        "__FLOOR__", tostring(var.apm.min_requests_per_second)),
        "__SPAN__", var.apm.span_name),
        "__APM__", var.apm.scope == "" ? "*" : var.apm.scope),
        ",__ASEL__}", var.apm.scope == "" ? "}" : ",${var.apm.scope}}"),
        "{__ASEL__}", var.apm.scope == "" ? "" : "{${var.apm.scope}}"),
        ",__BSEL__}", var.backing_services.scope == "" ? "}" : ",${var.backing_services.scope}}"),
        "{__BSEL__}", var.backing_services.scope == "" ? "" : "{${var.backing_services.scope}}"),
        ",__SEL__}", var.workload_scope == "" ? "}" : ",${var.workload_scope}}"),
        "{__SEL__}", var.workload_scope == "" ? "" : "{${var.workload_scope}}"),
        "__SCOPE__", local.datadog_scope[id]),
        "__TAGS__", "\"${var.cluster_scope}\""),
        "__WINDOW__", try(r.window, null) == null ? "" : r.window),
        "__LAST__", tostring(r.threshold + 1),
      ) if contains(keys(r), field)
    })
    if !contains(var.disabled_rules, id) && (try(r.requires, null) == null ? true : local.enabled[r.requires])
  }

  unknown_ids = setsubtract(setunion(var.disabled_rules, keys(var.overrides)), keys(local.backend_rules))
}
