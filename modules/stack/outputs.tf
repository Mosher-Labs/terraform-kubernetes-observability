output "grafana_admin_secret" {
  # Wait for the install, so anything using this output runs after it.
  depends_on = [helm_release.kube_prometheus_stack]

  description = "Namespace and name of the Secret holding the Grafana admin user and password, when kube_prometheus_stack is enabled."
  value       = var.kube_prometheus_stack.enabled ? { name = "${var.kube_prometheus_stack.release_name}-grafana", namespace = var.namespace } : null
}

output "grafana_service" {
  # Wait for the install, so anything using this output runs after it.
  depends_on = [helm_release.kube_prometheus_stack]

  description = "In-cluster URL of Grafana, when kube_prometheus_stack is enabled."
  value       = var.kube_prometheus_stack.enabled ? "http://${var.kube_prometheus_stack.release_name}-grafana.${var.namespace}.svc.cluster.local" : null
}

output "installed" {
  description = "The components this module installed."
  value = compact([
    var.alloy.enabled ? "alloy" : "",
    var.blackbox_exporter.enabled ? "blackbox_exporter" : "",
    var.kube_prometheus_stack.enabled ? "kube_prometheus_stack" : "",
    var.loki.enabled ? "loki" : "",
  ])
}

output "loki_datasource_uid" {
  # Wait for the install, so anything using this output runs after it.
  depends_on = [helm_release.kube_prometheus_stack, helm_release.loki]

  description = "UID of the Loki datasource added to Grafana, when loki and kube_prometheus_stack are both enabled."
  value       = var.loki.enabled && var.kube_prometheus_stack.enabled ? "loki" : null
}

output "loki_url" {
  # Wait for the install, so anything using this output runs after it.
  depends_on = [helm_release.loki]

  description = "In-cluster URL of Loki, when loki is enabled."
  value       = var.loki.enabled ? local.loki_url : null
}

output "prometheus_datasource_uid" {
  # Wait for the install, so anything using this output runs after it.
  depends_on = [helm_release.kube_prometheus_stack]

  description = "UID of Grafana's Prometheus datasource, for the root module's prometheus_datasource_uid, when kube_prometheus_stack is enabled."
  value       = var.kube_prometheus_stack.enabled ? "prometheus" : null
}
