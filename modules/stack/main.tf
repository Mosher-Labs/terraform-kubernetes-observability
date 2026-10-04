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
