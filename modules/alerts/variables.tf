variable "cluster_name" {
  description = "Name of the cluster. Added to every alert as the `cluster` label and to each rule title, so alerts from several clusters stay distinguishable in one Grafana."
  type        = string
}

variable "cluster_type" {
  description = "Kind of cluster: eks, aks, gke, openshift, k3s or generic. Managed control planes (eks, aks, gke) don't expose API server or etcd metrics, so those rules are left out for them."
  type        = string
  default     = "generic"

  validation {
    condition     = contains(["eks", "aks", "gke", "openshift", "k3s", "generic"], var.cluster_type)
    error_message = "cluster_type must be one of eks, aks, gke, openshift, k3s or generic."
  }
}

variable "control_plane" {
  description = "Override which control-plane metrics exist. Null keeps the cluster_type default. For example, k3s only has etcd metrics when it runs embedded etcd instead of the default SQLite."
  type = object({
    apiserver = optional(bool)
    etcd      = optional(bool)
  })
  default = {}
}

variable "disabled_rules" {
  description = "IDs of catalog rules to leave out, such as `node_network_errors`."
  type        = set(string)
  default     = []
}

variable "evaluation_interval_seconds" {
  description = "How often Grafana evaluates each rule group."
  type        = number
  default     = 60
}

variable "folder_title" {
  description = "Title of the Grafana folder that holds the alert rules. Defaults to \"Kubernetes alerts (<cluster_name>)\"."
  type        = string
  default     = null
}

variable "labels" {
  description = "Extra labels added to every alert, for routing or ownership."
  type        = map(string)
  default     = {}
}

variable "overrides" {
  description = "Per-rule changes, keyed by rule ID: threshold, pending period (`for`), severity, or a paused flag."
  type = map(object({
    threshold = optional(number)
    for       = optional(string)
    severity  = optional(string)
    paused    = optional(bool)
  }))
  default = {}

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
  description = "PromQL label matchers added to every workload rule, to scope them. For example `namespace!=\"kube-system\"`. Empty means all namespaces."
  type        = string
  default     = ""
}
