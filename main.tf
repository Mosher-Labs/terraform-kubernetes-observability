module "alerts" {
  source = "./modules/alerts"
  count  = var.alerts.enabled ? 1 : 0

  cluster_name                = var.cluster_name
  cluster_type                = var.cluster_type
  prometheus_datasource_uid   = var.prometheus_datasource_uid
  control_plane               = var.alerts.control_plane
  disabled_rules              = var.alerts.disabled_rules
  evaluation_interval_seconds = var.alerts.evaluation_interval_seconds
  folder_title                = var.alerts.folder_title
  labels                      = var.alerts.labels
  overrides                   = var.alerts.overrides
  workload_selector           = var.alerts.workload_selector
}

module "notifications" {
  source = "./modules/notifications"
  count  = var.notifications.enabled ? 1 : 0

  contact_point_name         = coalesce(var.notifications.contact_point_name, "kubernetes-${var.cluster_name}")
  manage_notification_policy = var.notifications.manage_notification_policy
  policy                     = var.notifications.policy
  email                      = var.notifications.email
  slack                      = var.slack
  teams                      = var.teams
  webex                      = var.webex
}
