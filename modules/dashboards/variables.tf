variable "cluster_name" {
  description = "Name of the cluster. Used in the dashboard title, its UID, and the alert list filter on the `cluster` label."
  type        = string
}

variable "folder_title" {
  default     = null
  description = "Title of the Grafana folder for the dashboard. Defaults to \"Kubernetes dashboards (<cluster_name>)\"."
  type        = string
}

variable "loki_datasource_uid" {
  default     = null
  description = "UID of a Loki datasource with the cluster's logs, labeled with `cluster` and `namespace` (as modules/stack's Alloy does). Null leaves out the logs row."
  type        = string
}

variable "prometheus_datasource_uid" {
  description = "UID of the Prometheus-compatible Grafana datasource the panels query."
  type        = string
}

variable "refresh" {
  default     = "1m"
  nullable    = false
  description = "How often the dashboard refreshes."
  type        = string
}
