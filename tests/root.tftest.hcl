mock_provider "grafana" {}

variables {
  cluster_name              = "homelab"
  cluster_type              = "k3s"
  prometheus_datasource_uid = "prometheus"
}

run "defaults_create_alerts_and_notifications" {
  command = plan

  variables {
    slack = { url = "https://hooks.slack.com/services/T000/B000/XXXX" }
  }

  assert {
    condition     = length(output.alert_rule_ids) == 25 && output.enabled_channels == tolist(["slack"])
    error_message = "The root module should create the k3s catalog and a Slack contact point."
  }

  assert {
    condition     = output.contact_point_name == "kubernetes-homelab"
    error_message = "The contact point should default to kubernetes-<cluster_name>."
  }
}

run "alerts_only" {
  command = plan

  variables {
    notifications = { enabled = false }
  }

  assert {
    condition     = output.contact_point_name == null && length(output.alert_rule_ids) > 0
    error_message = "Turning notifications off should still create the alerts."
  }
}

run "null_title_template_falls_back_to_default" {
  command = plan

  variables {
    slack = { url = "https://hooks.slack.com/services/T000/B000/XXXX" }
  }

  assert {
    condition     = nonsensitive(strcontains(module.notifications[0].contact_point_title, "FIRING"))
    error_message = "Leaving notifications.title_template unset should use the module default."
  }
}
