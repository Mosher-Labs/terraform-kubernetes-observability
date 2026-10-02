variable "cluster_name" {
  description = "Name of the cluster. Added to every alert as the `cluster` label and to each rule title, so alerts from several clusters stay distinguishable in one Grafana."
  type        = string
}

variable "cluster_type" {
  default     = "generic"
  description = "Kind of cluster: eks, aks, gke, openshift, k3s or generic. Managed control planes (eks, aks, gke) don't expose API server or etcd metrics, so those rules are left out for them."
  type        = string

  validation {
    condition     = contains(["eks", "aks", "gke", "openshift", "k3s", "generic"], var.cluster_type)
    error_message = "cluster_type must be one of eks, aks, gke, openshift, k3s or generic."
  }
}

variable "control_plane" {
  default     = {}
  description = "Override which control-plane metrics exist. Null keeps the cluster_type default. For example, k3s only has etcd metrics when it runs embedded etcd instead of the default SQLite."
  type = object({
    apiserver = optional(bool)
    etcd      = optional(bool)
  })
}

variable "disabled_rules" {
  default     = []
  description = "IDs of catalog rules to leave out, such as `node_network_errors`."
  type        = set(string)
}

variable "evaluation_interval_seconds" {
  default     = 60
  description = "How often Grafana evaluates each rule group."
  type        = number
}

variable "folder_title" {
  default     = null
  description = "Title of the Grafana folder that holds the alert rules. Defaults to \"Kubernetes alerts (<cluster_name>)\"."
  type        = string
}

variable "labels" {
  default     = {}
  description = "Extra labels added to every alert, for routing or ownership."
  type        = map(string)
}

variable "overrides" {
  default     = {}
  description = "Per-rule changes, keyed by rule ID: threshold, pending period (how long the condition must hold before the alert fires, such as \"10m\"), severity, or a paused flag."
  type = map(object({
    paused         = optional(bool)
    pending_period = optional(string)
    severity       = optional(string)
    threshold      = optional(number)
  }))

  validation {
    condition     = alltrue([for o in values(var.overrides) : o.severity == null || contains(["critical", "warning", "info"], coalesce(o.severity, "none"))])
    error_message = "An override's severity must be critical, warning or info."
  }
}

variable "prometheus_datasource_uid" {
  description = "UID of the Prometheus-compatible Grafana datasource the rules query."
  type        = string
}

variable "workload_selector" {
  default     = ""
  description = "PromQL label matchers added to every workload rule, to scope them. For example `namespace!=\"kube-system\"`. Empty means all namespaces."
  type        = string
}
