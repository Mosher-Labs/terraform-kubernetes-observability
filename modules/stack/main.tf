resource "helm_release" "alloy" {
  count = var.alloy.enabled ? 1 : 0
  # Ship logs only once Loki is up to receive them.
  depends_on = [helm_release.loki]

  chart            = "alloy"
  create_namespace = var.create_namespace
  name             = var.alloy.release_name
  namespace        = var.namespace
  repository       = "https://grafana.github.io/helm-charts"
  timeout          = var.timeout_seconds
  values           = concat([local.alloy_values], var.alloy.values)
  version          = var.alloy.chart_version

  lifecycle {
    precondition {
      condition     = var.loki.enabled || var.alloy.push_url != null
      error_message = "alloy needs loki.enabled, or alloy.push_url for a Loki installed elsewhere."
    }
  }
}

resource "helm_release" "blackbox_exporter" {
  count = var.blackbox_exporter.enabled ? 1 : 0
  # The ServiceMonitor needs kube-prometheus-stack's CRDs.
  depends_on = [helm_release.kube_prometheus_stack]

  chart            = "prometheus-blackbox-exporter"
  create_namespace = var.create_namespace
  name             = var.blackbox_exporter.release_name
  namespace        = var.namespace
  repository       = "https://prometheus-community.github.io/helm-charts"
  timeout          = var.timeout_seconds
  values           = concat([local.blackbox_values], var.blackbox_exporter.values)
  version          = var.blackbox_exporter.chart_version
}

resource "helm_release" "datadog_agent" {
  count = var.datadog_agent.enabled ? 1 : 0

  chart            = "datadog"
  create_namespace = var.create_namespace
  name             = var.datadog_agent.release_name
  namespace        = var.namespace
  repository       = "https://helm.datadoghq.com"
  # The API key, only when no existing Secret is named.
  set_sensitive = var.datadog_agent.api_key_secret_name == null && var.datadog_api_key != null ? [{ name = "datadog.apiKey", value = var.datadog_api_key }] : null
  timeout       = var.timeout_seconds
  # Helm merges these in order: the module's base, the cluster type's, the
  # control-plane checks', then the caller's.
  values  = concat([local.datadog_values, local.datadog_cluster_values[var.cluster_type], local.datadog_control_plane_values], var.datadog_agent.values)
  version = var.datadog_agent.chart_version

  lifecycle {
    precondition {
      condition     = var.datadog_agent.api_key_secret_name != null || nonsensitive(var.datadog_api_key != null)
      error_message = "datadog_agent needs api_key_secret_name, or datadog_api_key."
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  count = var.kube_prometheus_stack.enabled ? 1 : 0

  chart            = "kube-prometheus-stack"
  create_namespace = var.create_namespace
  name             = var.kube_prometheus_stack.release_name
  namespace        = var.namespace
  repository       = "https://prometheus-community.github.io/helm-charts"
  timeout          = var.timeout_seconds
  values           = concat([local.kube_prometheus_stack_values], var.kube_prometheus_stack.values)
  version          = var.kube_prometheus_stack.chart_version
}

resource "helm_release" "loki" {
  count = var.loki.enabled ? 1 : 0

  chart            = "loki"
  create_namespace = var.create_namespace
  name             = var.loki.release_name
  namespace        = var.namespace
  repository       = "https://grafana.github.io/helm-charts"
  timeout          = var.timeout_seconds
  values           = concat([local.loki_values], var.loki.values)
  version          = var.loki.chart_version
}

resource "helm_release" "opentelemetry" {
  count = var.opentelemetry.enabled ? 1 : 0
  # The collector's ServiceMonitor needs kube-prometheus-stack's CRDs.
  depends_on = [helm_release.kube_prometheus_stack]

  chart            = "opentelemetry-kube-stack"
  create_namespace = var.create_namespace
  name             = var.opentelemetry.release_name
  namespace        = var.namespace
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  timeout          = var.timeout_seconds
  values           = concat([local.opentelemetry_values], var.opentelemetry.values)
  version          = var.opentelemetry.chart_version
}
