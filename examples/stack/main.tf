# Install the monitoring stack on a cluster that has none, then create the
# alerts in the Grafana it installed.
#
# Both modules can share one root because the Grafana provider's settings are
# known before anything is installed, and the stack's outputs wait for the
# Helm releases. Terraform must be able to reach Grafana at grafana_url once
# kube-prometheus-stack is up: through an ingress, or a port-forward started
# during the first apply. If that isn't practical, apply modules/stack from
# its own root first.

terraform {
  required_version = ">= 1.15.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 4.0.0, < 5.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0, < 4.0.0"
    }
  }
}

variable "grafana_auth" {
  description = "Grafana credentials as \"user:password\". kube-prometheus-stack stores the admin password in the Secret named by the stack's grafana_admin_secret output."
  sensitive   = true
  type        = string
}

variable "grafana_url" {
  description = "URL Terraform uses to reach the installed Grafana."
  type        = string
}

variable "kubeconfig_path" {
  default     = "~/.kube/config"
  description = "Kubeconfig for the cluster."
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL."
  sensitive   = true
  type        = string
}

provider "grafana" {
  auth = var.grafana_auth
  url  = var.grafana_url
}

provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

module "stack" {
  source = "../../modules/stack"

  alloy = { enabled = true }
  blackbox_exporter = {
    enabled = true
    targets = [
      { name = "homepage", url = "https://example.com" },
    ]
  }
  cluster_name          = "lab"
  kube_prometheus_stack = { enabled = true }
  loki                  = { enabled = true }
}

module "observability" {
  source = "../.."

  cluster_name              = "lab"
  cluster_type              = "k3s"
  prometheus_datasource_uid = module.stack.prometheus_datasource_uid
  slack                     = { url = var.slack_webhook_url }
}

output "installed" {
  description = "The components the stack installed."
  value       = module.stack.installed
}
