# Alerts for a k3s cluster whose Grafana and Prometheus already exist (for
# example from kube-prometheus-stack), sent to Slack and email.

terraform {
  required_version = ">= 1.15.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}

variable "grafana_token" {
  description = "Grafana service account token with permission to manage alerting and folders."
  sensitive   = true
  type        = string
}

variable "grafana_url" {
  description = "URL of the Grafana instance."
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL."
  sensitive   = true
  type        = string
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_token
}

module "observability" {
  source = "../.."

  alerts = {
    overrides = {
      node_disk_full = { threshold = 90 }
    }
    # Leave out noisy system namespaces.
    workload_selector = "namespace!~\"kube-system|kube-node-lease\""
  }
  cluster_name = "homelab"
  cluster_type = "k3s"
  notifications = {
    email = { addresses = ["oncall@example.com"] }
  }
  prometheus_datasource_uid = "prometheus"
  slack                     = { url = var.slack_webhook_url }
}

output "alert_rule_ids" {
  description = "The alert rules that were created."
  value       = module.observability.alert_rule_ids
}
