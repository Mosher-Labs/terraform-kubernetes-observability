# Install the Datadog Agent on a k3s cluster, then create the alert catalog as
# Datadog monitors that notify Slack and a Webex bot.
#
# Before the first apply, install the Datadog app in your Slack workspace from
# Datadog's Slack integration tile, and create the API key Secret:
#
#   kubectl create namespace monitoring
#   kubectl -n monitoring create secret generic datadog-secret --from-literal api-key=<key>

terraform {
  required_version = ">= 1.15.0"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = ">= 4.0.0, < 5.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0, < 4.0.0"
    }
  }
}

variable "datadog_api_key" {
  description = "Datadog API key, for the provider."
  sensitive   = true
  type        = string
}

variable "datadog_app_key" {
  description = "Datadog application key with permission to manage monitors and integrations."
  sensitive   = true
  type        = string
}

variable "kubeconfig_path" {
  default     = "~/.kube/config"
  description = "Kubeconfig for the cluster."
  type        = string
}

variable "webex_bot_token" {
  description = "Webex bot access token."
  sensitive   = true
  type        = string
}

variable "webex_room_id" {
  description = "ID of the Webex room the bot posts to."
  type        = string
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}

provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

module "stack" {
  source = "../../modules/stack"

  cluster_name = "homelab"
  cluster_type = "k3s"
  datadog_agent = {
    api_key_secret_name = "datadog-secret"
    enabled             = true
    logs                = true
  }
}

module "datadog_alerts" {
  source = "../../modules/datadog"

  apm              = { enabled = true, scope = "env:homelab" }
  backing_services = { postgres = { enabled = true } }
  cluster_name     = "homelab"
  disabled_rules   = ["node_network_errors"]
  notifications = {
    slack = { account_name = "example", channel = "homelab-alerts" }
    webex = { room_id = var.webex_room_id, token = var.webex_bot_token }
  }
  overrides = {
    node_disk_full = { threshold = 90 }
  }
  workload_scope = "NOT kube_namespace:kube-system"
}

output "monitor_ids" {
  description = "Datadog monitor IDs, keyed by rule ID."
  value       = module.datadog_alerts.monitor_ids
}
