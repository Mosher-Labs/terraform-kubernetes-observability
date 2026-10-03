locals {
  # k3s defaults to SQLite (kine), so it has an API server but no etcd.
  capabilities = {
    apiserver = coalesce(var.control_plane.apiserver, !local.managed_control_plane)
    etcd      = coalesce(var.control_plane.etcd, contains(["generic", "openshift"], var.cluster_type))
  }

  # Custom rule IDs that clash with a rule this module defines.
  colliding_ids = setintersection(keys(var.custom_rules), concat(keys(local.known_rules), local.backing_rule_ids))

  # The rules turned on: the core catalog, the optional groups, and custom rules.
  enabled_catalog = merge(local.catalog, { for id, r in local.apm_catalog : id => r if var.apm.enabled }, local.backing_catalog, var.custom_rules)

  groups = distinct([for r in values(local.rules) : r.group])

  # Every rule this module knows, enabled or not, for checking rule IDs.
  known_rules = merge(local.catalog, local.apm_catalog)

  managed_control_plane = contains(["aks", "eks", "gke"], var.cluster_type)

  rules = {
    for id, r in local.enabled_catalog : id => {
      expr = replace(
        replace(r.expr, ",__SEL__}", var.workload_selector == "" ? "}" : ",${var.workload_selector}}"),
        "{__SEL__}", var.workload_selector == "" ? "" : "{${var.workload_selector}}",
      )
      group          = r.group
      operator       = r.operator
      paused         = coalesce(try(var.overrides[id].paused, null), false)
      pending_period = coalesce(try(var.overrides[id].pending_period, null), r.pending_period)
      severity       = coalesce(try(var.overrides[id].severity, null), r.severity)
      subject        = r.subject
      summary        = r.summary
      threshold      = coalesce(try(var.overrides[id].threshold, null), r.threshold)
      title          = "[${var.cluster_name}] ${r.title}"
    }
    if !contains(var.disabled_rules, id) && (try(r.requires, null) == null ? true : local.capabilities[r.requires])
  }

  unknown_ids = setsubtract(setunion(var.disabled_rules, keys(var.overrides)), concat(keys(local.known_rules), local.backing_rule_ids, keys(var.custom_rules)))
}
