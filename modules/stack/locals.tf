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

  otel_collector_image = split(":", var.opentelemetry.collector_image)

  # The operator names the collector's Service "<collector name>-collector".
  otel_collector_url = "http://${var.opentelemetry.release_name}-collector.${var.namespace}.svc.cluster.local:4318"

  opentelemetry_values = yamlencode({
    clusterName = var.cluster_name
    crds = {
      installOtel = true
      # kube-prometheus-stack owns the Prometheus CRDs.
      installPrometheus = false
    }
    "opentelemetry-operator" = {
      admissionWebhooks = {
        # Reuse the certificate on upgrades. A new one on every render breaks
        # the webhook until the operator restarts.
        autoGenerateCert = { enabled = true, recreate = false }
        certManager      = { enabled = false }
      }
      manager = {
        autoInstrumentation = { go = { enabled = var.opentelemetry.go_auto_instrumentation } }
      }
    }
    collectors = {
      daemon = { enabled = false }
      spanmetrics = {
        config = {
          receivers = {
            otlp = {
              protocols = {
                grpc = { endpoint = "0.0.0.0:4317" }
                http = { endpoint = "0.0.0.0:4318" }
              }
            }
          }
          processors = {
            batch = {}
            # Request metrics come from server spans only.
            "filter/server-spans" = {
              error_mode = "ignore"
              traces     = { span = ["kind != SPAN_KIND_SERVER"] }
            }
          }
          connectors = {
            spanmetrics = {
              # "http.server.request" + "duration" in seconds becomes
              # http_server_request_duration_seconds in Prometheus.
              namespace = "http.server.request"
              histogram = {
                unit = "s"
                # OpenTelemetry's default HTTP buckets.
                explicit = { buckets = ["5ms", "10ms", "25ms", "50ms", "75ms", "100ms", "250ms", "500ms", "750ms", "1s", "2.5s", "5s", "7.5s", "10s"] }
              }
              dimensions = [
                { name = "http.request.method" },
                { name = "http.route" },
                { name = "http.response.status_code" },
                # A resource attribute the operator injects. The ServiceMonitor
                # turns it into the namespace label.
                { name = "k8s.namespace.name" },
              ]
            }
          }
          exporters = {
            prometheus = { endpoint = "0.0.0.0:8889" }
          }
          service = {
            pipelines = {
              traces = {
                receivers  = ["otlp"]
                processors = ["filter/server-spans", "batch"]
                exporters  = ["spanmetrics"]
              }
              metrics = {
                receivers  = ["otlp", "spanmetrics"]
                processors = ["batch"]
                exporters  = ["prometheus"]
              }
            }
          }
        }
        fullnameOverride = var.opentelemetry.release_name
        image = {
          repository = local.otel_collector_image[0]
          tag        = local.otel_collector_image[1]
        }
        mode     = "deployment"
        ports    = [{ name = "metrics", port = 8889, protocol = "TCP" }]
        replicas = 1
        enabled  = true
      }
    }
    instrumentation = {
      enabled     = true
      exporter    = { endpoint = local.otel_collector_url }
      propagators = ["tracecontext", "baggage"]
      sampler     = { type = "parentbased_always_on" }
      # The chart creates this before the operator's webhook is ready, so
      # the webhook can't fill in the agent images and pods that opt in get
      # an empty image. Set them here: the defaults of the operator the chart
      # ships (0.159.0). Update them with chart_version.
      dotnet = { image = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-dotnet:1.16.0" }
      go     = { image = "ghcr.io/open-telemetry/opentelemetry-go-instrumentation/autoinstrumentation-go:v0.24.0" }
      java   = { image = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2.31.1" }
      nodejs = { image = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.78.0" }
      python = { image = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.65b0" }
    }
    extraObjects = var.kube_prometheus_stack.enabled ? [{
      apiVersion = "monitoring.coreos.com/v1"
      kind       = "ServiceMonitor"
      metadata = {
        name = "${var.opentelemetry.release_name}-spanmetrics"
        # kube-prometheus-stack only picks up ServiceMonitors with its release
        # label.
        labels = { release = var.kube_prometheus_stack.release_name }
      }
      spec = {
        endpoints = [{
          port     = "metrics"
          interval = "30s"
          # Keep the job label the exporter sets from each app's service.name.
          honorLabels = true
          # Prometheus would set namespace to the collector's namespace. Use
          # the app's, so alerts that join on namespace match its deployments.
          metricRelabelings = [
            { sourceLabels = ["k8s_namespace_name"], regex = "(.+)", targetLabel = "namespace" },
            { regex = "k8s_namespace_name", action = "labeldrop" },
          ]
        }]
        selector = {
          matchLabels = {
            "app.kubernetes.io/component" = "opentelemetry-collector"
            "app.kubernetes.io/instance"  = "${var.namespace}.${var.opentelemetry.release_name}"
            # The operator also makes a headless Service with the same ports.
            # Scrape only the base one, or every series is scraped twice.
            "operator.opentelemetry.io/collector-service-type" = "base"
          }
        }
      }
    }] : []
  })
}
