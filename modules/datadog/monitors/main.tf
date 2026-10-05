# The catalog holds every rule once for both backends. This module takes the
# Datadog rules from it and adds what a monitor needs: the comparison, the
# message and the tags.
module "catalog" {
  source = "../../catalog"

  apm              = var.apm
  backing_services = var.backing_services
  catalog          = "datadog"
  cluster_scope    = local.cluster_scope
  control_plane    = var.control_plane
  disabled_rules   = var.disabled_rules
  overrides        = var.overrides
  # The monitors output checks the IDs, so its error comes from here.
  validate_rule_ids = false
  workload_scope    = var.workload_scope
}
