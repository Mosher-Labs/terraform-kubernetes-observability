module "alerts" {
  count  = var.alerts.enabled ? 1 : 0
  source = "./modules/alerts"

  cluster_name                = var.cluster_name
  cluster_type                = var.cluster_type
  control_plane               = var.alerts.control_plane
  disabled_rules              = var.alerts.disabled_rules
  evaluation_interval_seconds = var.alerts.evaluation_interval_seconds
  folder_title                = var.alerts.folder_title
  labels                      = var.alerts.labels
  overrides                   = var.alerts.overrides
  prometheus_datasource_uid   = var.prometheus_datasource_uid
  workload_selector           = var.alerts.workload_selector
}

module "dashboards" {
  count  = var.dashboards.enabled ? 1 : 0
  source = "./modules/dashboards"

  cluster_name              = var.cluster_name
  folder_title              = var.dashboards.folder_title
  loki_datasource_uid       = var.dashboards.loki_datasource_uid
  prometheus_datasource_uid = var.prometheus_datasource_uid
  refresh                   = var.dashboards.refresh
}

module "notifications" {
  count  = var.notifications.enabled ? 1 : 0
  source = "./modules/notifications"

  contact_point_name         = coalesce(var.notifications.contact_point_name, "kubernetes-${var.cluster_name}")
  email                      = var.notifications.email
  manage_notification_policy = var.notifications.manage_notification_policy
  policy                     = var.notifications.policy
  slack                      = var.slack
  teams                      = var.teams
  title_template             = var.notifications.title_template
  webex                      = var.webex
}
