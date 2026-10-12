locals {
  # k3s defaults to SQLite (kine), so it has an API server but no etcd.
  capabilities = {
    apiserver = coalesce(var.control_plane.apiserver, !local.managed_control_plane)
    etcd      = coalesce(var.control_plane.etcd, contains(["generic", "openshift"], var.cluster_type))
  }

  # Custom rule IDs that clash with a rule this module defines.
  colliding_ids = setintersection(keys(var.custom_rules), module.catalog.known_rule_ids)

  groups = distinct([for r in values(local.rules) : r.group])

  managed_control_plane = contains(["aks", "eks", "gke"], var.cluster_type)

  # The catalog's rules, then the caller's own. Both take the same overrides and
  # disabled_rules.
  rules = merge(
    {
      for id, r in module.catalog.rules : id => {
        expr           = r.expr
        group          = r.group
        operator       = r.operator
        paused         = r.paused
        pending_period = r.pending_period
        severity       = r.severity
        subject        = r.subject
        summary        = r.summary
        threshold      = r.threshold
        title          = "[${var.cluster_name}] ${r.title}"
      }
    },
    {
      for id, r in var.custom_rules : id => {
        expr           = r.expr
        group          = r.group
        operator       = r.operator
        paused         = coalesce(try(var.overrides[id].paused, null), false)
        pending_period = coalesce(try(var.overrides[id].pending_period, null), r.pending_period)
        severity       = coalesce(try(var.overrides[id].severity, null), r.severity)
        subject        = r.subject
        summary        = r.summary
        threshold      = coalesce(try(var.overrides[id].threshold, null), r.threshold)
        title          = "[${var.cluster_name}] ${r.title}"
      } if !contains(var.disabled_rules, id)
    },
  )

  # Each rule's runbook link, for rules that have one. A URL in urls wins over
  # base_url.
  runbook_urls = {
    for id in keys(local.rules) : id => lookup(var.runbooks.urls, id, "${coalesce(var.runbooks.base_url, "")}${id}.md")
    if contains(keys(var.runbooks.urls), id) || contains(var.runbooks.rule_ids, id)
  }

  # Rules that page with nowhere to go. Every critical rule should have a
  # runbook; a warning or info rule can do without.
  rules_without_runbook = sort([for id, r in local.rules : id if r.severity == "critical" && !contains(keys(local.runbook_urls), id)])

  unknown_ids = setsubtract(setunion(var.disabled_rules, keys(var.overrides), var.runbooks.rule_ids, keys(var.runbooks.urls)), setunion(module.catalog.known_rule_ids, keys(var.custom_rules)))
}
