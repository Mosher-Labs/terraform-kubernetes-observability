# The alert catalog lives in modules/catalog, which holds every rule once for
# both backends. This module asks it for the grafana rules and creates them.
#
# `requires` in the catalog names the capability a rule needs: "apiserver" and
# "etcd" are control-plane metrics that managed clusters (EKS, AKS, GKE) don't
# expose, so local.capabilities turns them off there.
module "catalog" {
  source = "../catalog"

  # The catalog's `scope` is the grafana selector here.
  apm = merge(var.apm, {
    scope = var.apm.selector
  })
  backing_services = merge(var.backing_services, {
    scope = var.backing_services.selector
  })
  catalog        = "grafana"
  control_plane  = local.capabilities
  disabled_rules = var.disabled_rules
  overrides      = var.overrides
  # This module checks the IDs itself, since custom_rules adds more.
  validate_rule_ids = false
  workload_scope    = var.workload_selector
}
