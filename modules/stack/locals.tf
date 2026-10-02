locals {
  alloy_values = yamlencode({
    alloy = {
      configMap = {
        content = <<-EOT
          discovery.kubernetes "pods" {
            role = "pod"
          }

          discovery.relabel "pods" {
            targets = discovery.kubernetes.pods.targets

            rule {
              source_labels = ["__meta_kubernetes_namespace"]
              target_label  = "namespace"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label  = "pod"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_container_name"]
              target_label  = "container"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
              target_label  = "app"
            }
          }

          loki.source.kubernetes "pods" {
            targets    = discovery.relabel.pods.output
            forward_to = [loki.write.default.receiver]
          }

          loki.write "default" {
            endpoint {
              url = "${local.loki_push_url}"
            }
            external_labels = {
              cluster = "${var.cluster_name}",
            }
          }
        EOT
      }
    }
    # loki.source.kubernetes tails logs through the API server, so one replica
    # sees every pod. A DaemonSet would ship each line once per node.
    controller = {
      replicas = 1
      type     = "deployment"
    }
  })

  blackbox_values = yamlencode({
    serviceMonitor = {
      defaults = {
        # kube-prometheus-stack only picks up ServiceMonitors with its release
        # label.
        labels = var.kube_prometheus_stack.enabled ? { release = var.kube_prometheus_stack.release_name } : {}
      }
      enabled = var.kube_prometheus_stack.enabled
      targets = [for t in var.blackbox_exporter.targets : {
        interval = t.interval
        module   = t.module
        name     = t.name
        url      = t.url
      }]
    }
  })

  kube_prometheus_stack_values = yamlencode({
    grafana = {
      additionalDataSources = var.loki.enabled ? [{
        access = "proxy"
        name   = "Loki"
        type   = "loki"
        uid    = "loki"
        url    = local.loki_url
      }] : []
    }
  })

  loki_push_url = coalesce(var.alloy.push_url, "${local.loki_url}/loki/api/v1/push")

  loki_url = "http://${var.loki.release_name}.${var.namespace}.svc.cluster.local:3100"

  loki_values = yamlencode({
    backend        = { replicas = 0 }
    chunksCache    = { enabled = false }
    deploymentMode = "SingleBinary"
    gateway        = { enabled = false }
    loki = {
      auth_enabled = false
      commonConfig = { replication_factor = 1 }
      compactor = {
        delete_request_store = "filesystem"
        retention_enabled    = true
      }
      limits_config = { retention_period = var.loki.retention }
      schemaConfig = {
        configs = [{
          from         = "2024-04-01"
          index        = { period = "24h", prefix = "loki_index_" }
          object_store = "filesystem"
          schema       = "v13"
          store        = "tsdb"
        }]
      }
      storage = { type = "filesystem" }
    }
    lokiCanary   = { enabled = false }
    read         = { replicas = 0 }
    resultsCache = { enabled = false }
    singleBinary = {
      persistence = { enabled = true, size = var.loki.storage_size }
      replicas    = 1
    }
    test  = { enabled = false }
    write = { replicas = 0 }
  })
}
