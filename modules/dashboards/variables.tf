variable "apm" {
  default     = {}
  description = "Service-level metrics for the Services row: the same settings as modules/alerts' apm. The row appears when `enabled` is true."
  type = object({
    enabled       = optional(bool, false)
    metric        = optional(string, "http_server_request_duration_seconds")
    route_label   = optional(string, "http_route")
    selector      = optional(string, "")
    service_label = optional(string, "job")
    status_label  = optional(string, "http_response_status_code")
  })
}

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

variable "slos" {
  default     = {}
  description = "SLOs to show on their own dashboard, one row each: the SLI and the error budget left over the SLO window, and the burn rates the alerts use. Pass `module.slo.dashboard_slos` from `modules/slo`. Prometheus needs data for the whole `window_days` for the budget to be right."
  type = map(object({
    budget_remaining = string
    burn_rates       = map(string)
    sli              = string
    target           = number
    title            = string
    window_days      = number
  }))
}
