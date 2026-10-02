# Alerts for a k3s cluster whose Grafana and Prometheus already exist (for
# example from kube-prometheus-stack), sent to Slack and email.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}

variable "grafana_url" {
  description = "URL of the Grafana instance."
  type        = string
}

variable "grafana_token" {
  description = "Grafana service account token with permission to manage alerting and folders."
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL."
  type        = string
  sensitive   = true
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_token
}

module "observability" {
  source = "../.."

  cluster_name              = "homelab"
  cluster_type              = "k3s"
  prometheus_datasource_uid = "prometheus"

  alerts = {
    # Leave out noisy system namespaces.
    workload_selector = "namespace!~\"kube-system|kube-node-lease\""
    overrides = {
      node_disk_full = { threshold = 90 }
    }
  }

  slack = { url = var.slack_webhook_url }

  notifications = {
    email = { addresses = ["oncall@example.com"] }
  }
}

output "alert_rule_ids" {
  description = "The alert rules that were created."
  value       = module.observability.alert_rule_ids
}
