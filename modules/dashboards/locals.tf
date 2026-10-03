locals {
  dashboard = {
    panels        = [for i, p in local.panel_specs : merge(local.panel_defaults[p.kind], p.panel, { id = i + 1 })]
    refresh       = var.refresh
    schemaVersion = 39
    tags          = ["kubernetes", "terraform-kubernetes-observability"]
    templating = {
      list = [{
        allValue   = ".*"
        current    = { text = "All", value = "$__all" }
        datasource = local.prometheus
        definition = "label_values(kube_namespace_status_phase, namespace)"
        includeAll = true
        label      = "Namespace"
        multi      = true
        name       = "namespace"
        query      = { query = "label_values(kube_namespace_status_phase, namespace)", refId = "namespaces" }
        refresh    = 2
        sort       = 1
        type       = "query"
      }]
    }
    time     = { from = "now-6h", to = "now" }
    timezone = "browser"
    title    = "Kubernetes overview (${var.cluster_name})"
    uid      = substr("k8s-overview-${replace(lower(var.cluster_name), "/[^a-z0-9-]/", "-")}", 0, 40)
  }

  loki = var.loki_datasource_uid == null ? null : { type = "loki", uid = var.loki_datasource_uid }

  # Matchers for the namespace variable, in PromQL and LogQL.
  ns = "namespace=~\"$namespace\""

  # Settings each panel kind starts from; panel_specs fill in the rest.
  panel_defaults = {
    alertlist = {
      type = "alertlist"
    }
    logs = {
      datasource = local.loki
      options    = { enableLogDetails = true, showTime = true, sortOrder = "Descending", wrapLogMessage = true }
      type       = "logs"
    }
    row = {
      collapsed = false
      panels    = []
      type      = "row"
    }
    stat = {
      datasource = local.prometheus
      options = {
        colorMode     = "background"
        graphMode     = "none"
        reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }
        textMode      = "value"
      }
      type = "stat"
    }
    table = {
      datasource = local.prometheus
      options    = { showHeader = true }
      type       = "table"
    }
    timeseries = {
      datasource = local.prometheus
      options = {
        legend  = { displayMode = "list", placement = "bottom", showLegend = true }
        tooltip = { mode = "multi", sort = "desc" }
      }
      type = "timeseries"
    }
  }

  # Panels top to bottom. Each needs a gridPos (24 columns wide).
  panel_specs = concat(
    [
      { kind = "row", panel = { gridPos = { h = 1, w = 24, x = 0, y = 0 }, title = "Overview" } },
      {
        kind = "stat"
        panel = {
          fieldConfig = local.stat_thresholds_zero_good
          gridPos     = { h = 4, w = 4, x = 0, y = 1 }
          targets     = [{ datasource = local.prometheus, expr = "sum(kube_node_status_condition{condition=\"Ready\",status=~\"false|unknown\"}) or vector(0)", legendFormat = "", range = true, refId = "A" }]
          title       = "Nodes not ready"
        }
      },
      {
        kind = "stat"
        panel = {
          fieldConfig = local.stat_thresholds_zero_good
          gridPos     = { h = 4, w = 4, x = 4, y = 1 }
          targets     = [{ datasource = local.prometheus, expr = "sum(kube_pod_status_phase{phase=~\"Pending|Failed|Unknown\",${local.ns}}) or vector(0)", legendFormat = "", range = true, refId = "A" }]
          title       = "Pods not running"
        }
      },
      {
        kind = "stat"
        panel = {
          fieldConfig = local.stat_thresholds_zero_good
          gridPos     = { h = 4, w = 4, x = 8, y = 1 }
          targets     = [{ datasource = local.prometheus, expr = "round(sum(increase(kube_pod_container_status_restarts_total{${local.ns}}[1h]))) or vector(0)", legendFormat = "", range = true, refId = "A" }]
          title       = "Container restarts (1h)"
        }
      },
      {
        kind = "stat"
        panel = {
          fieldConfig = local.stat_thresholds_zero_good
          gridPos     = { h = 4, w = 4, x = 0, y = 5 }
          targets     = [{ datasource = local.prometheus, expr = "sum(kube_deployment_spec_replicas{${local.ns}} - kube_deployment_status_replicas_available{${local.ns}} > 0) or vector(0)", legendFormat = "", range = true, refId = "A" }]
          title       = "Missing deployment replicas"
        }
      },
      {
        kind = "stat"
        panel = {
          fieldConfig = local.stat_thresholds_zero_good
          gridPos     = { h = 4, w = 4, x = 4, y = 5 }
          targets     = [{ datasource = local.prometheus, expr = "count(probe_success == 0) or vector(0)", legendFormat = "", range = true, refId = "A" }]
          title       = "Synthetic checks failing"
        }
      },
      {
        kind = "stat"
        panel = {
          fieldConfig = local.stat_thresholds_zero_good
          gridPos     = { h = 4, w = 4, x = 8, y = 5 }
          targets     = [{ datasource = local.prometheus, expr = "count(min by (job, instance) (up) == 0) or vector(0)", legendFormat = "", range = true, refId = "A" }]
          title       = "Metrics targets down"
        }
      },
      {
        kind = "alertlist"
        panel = {
          gridPos = { h = 8, w = 12, x = 12, y = 1 }
          options = {
            alertInstanceLabelFilter = "{cluster=\"${var.cluster_name}\", heartbeat!=\"true\"}"
            dashboardAlerts          = false
            groupMode                = "default"
            maxItems                 = 20
            sortOrder                = 1
            stateFilter              = { error = true, firing = true, noData = false, normal = false, pending = true }
            viewMode                 = "list"
          }
          title = "Firing and pending alerts"
        }
      },

      { kind = "row", panel = { gridPos = { h = 1, w = 24, x = 0, y = 9 }, title = "Resources" } },
      {
        kind = "timeseries"
        panel = {
          fieldConfig = { defaults = { unit = "cores" }, overrides = [] }
          gridPos     = { h = 8, w = 12, x = 0, y = 10 }
          targets     = [{ datasource = local.prometheus, expr = "sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=\"\",${local.ns}}[5m]))", legendFormat = "{{namespace}}", range = true, refId = "A" }]
          title       = "CPU by namespace"
        }
      },
      {
        kind = "timeseries"
        panel = {
          fieldConfig = { defaults = { unit = "bytes" }, overrides = [] }
          gridPos     = { h = 8, w = 12, x = 12, y = 10 }
          targets     = [{ datasource = local.prometheus, expr = "sum by (namespace) (container_memory_working_set_bytes{container!=\"\",${local.ns}})", legendFormat = "{{namespace}}", range = true, refId = "A" }]
          title       = "Memory by namespace"
        }
      },
      {
        kind = "table"
        panel = {
          fieldConfig     = { defaults = { decimals = 0, unit = "percent" }, overrides = [] }
          gridPos         = { h = 8, w = 12, x = 0, y = 18 }
          targets         = [{ datasource = local.prometheus, expr = "topk(10, 100 * max by (namespace, pod, container) (container_memory_working_set_bytes{container!=\"\",${local.ns}} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"memory\",${local.ns}}))", format = "table", instant = true, refId = "A" }]
          title           = "Top containers by memory, % of limit"
          transformations = local.table_transformations
        }
      },
      {
        kind = "table"
        panel = {
          fieldConfig     = { defaults = { decimals = 0, unit = "percent" }, overrides = [] }
          gridPos         = { h = 8, w = 12, x = 12, y = 18 }
          targets         = [{ datasource = local.prometheus, expr = "topk(10, 100 * max by (namespace, pod, container) (increase(container_cpu_cfs_throttled_periods_total{container!=\"\",${local.ns}}[5m]) / increase(container_cpu_cfs_periods_total{container!=\"\",${local.ns}}[5m])))", format = "table", instant = true, refId = "A" }]
          title           = "Top containers by CPU throttling, % of periods"
          transformations = local.table_transformations
        }
      },
      {
        kind = "timeseries"
        panel = {
          fieldConfig = { defaults = { max = 100, min = 0, unit = "percent" }, overrides = [] }
          gridPos     = { h = 8, w = 12, x = 0, y = 26 }
          targets     = [{ datasource = local.prometheus, expr = "100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])))", legendFormat = "{{instance}}", range = true, refId = "A" }]
          title       = "Node CPU"
        }
      },
      {
        kind = "timeseries"
        panel = {
          fieldConfig = { defaults = { max = 100, min = 0, unit = "percent" }, overrides = [] }
          gridPos     = { h = 8, w = 12, x = 12, y = 26 }
          targets     = [{ datasource = local.prometheus, expr = "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)", legendFormat = "{{instance}}", range = true, refId = "A" }]
          title       = "Node memory"
        }
      },

      { kind = "row", panel = { gridPos = { h = 1, w = 24, x = 0, y = 34 }, title = "Workloads" } },
      {
        kind = "timeseries"
        panel = {
          fieldConfig = { defaults = { decimals = 0, unit = "none" }, overrides = [] }
          gridPos     = { h = 8, w = 12, x = 0, y = 35 }
          targets     = [{ datasource = local.prometheus, expr = "topk(10, sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total{${local.ns}}[1h]))) > 0", legendFormat = "{{namespace}}/{{pod}}", range = true, refId = "A" }]
          title       = "Restarts per pod (1h)"
        }
      },
      {
        kind = "table"
        panel = {
          fieldConfig     = { defaults = { decimals = 0, unit = "none" }, overrides = [] }
          gridPos         = { h = 8, w = 12, x = 12, y = 35 }
          targets         = [{ datasource = local.prometheus, expr = "max by (namespace, deployment) (kube_deployment_spec_replicas{${local.ns}} - kube_deployment_status_replicas_available{${local.ns}}) > 0", format = "table", instant = true, refId = "A" }]
          title           = "Deployments missing replicas"
          transformations = local.table_transformations
        }
      },

      { kind = "row", panel = { gridPos = { h = 1, w = 24, x = 0, y = 43 }, title = "Synthetic checks" } },
      {
        kind = "table"
        panel = {
          fieldConfig = {
            defaults = {
              mappings = [{ options = { "0" = { color = "red", text = "Down" }, "1" = { color = "green", text = "Up" } }, type = "value" }]
              unit     = "none"
            }
            overrides = []
          }
          gridPos         = { h = 8, w = 8, x = 0, y = 44 }
          targets         = [{ datasource = local.prometheus, expr = "min by (target, instance) (probe_success)", format = "table", instant = true, refId = "A" }]
          title           = "Status"
          transformations = local.table_transformations
        }
      },
      {
        kind = "timeseries"
        panel = {
          fieldConfig = { defaults = { unit = "s" }, overrides = [] }
          gridPos     = { h = 8, w = 8, x = 8, y = 44 }
          targets     = [{ datasource = local.prometheus, expr = "max by (target) (probe_duration_seconds)", legendFormat = "{{target}}", range = true, refId = "A" }]
          title       = "Response time"
        }
      },
      {
        kind = "table"
        panel = {
          fieldConfig     = { defaults = { decimals = 0, unit = "d" }, overrides = [] }
          gridPos         = { h = 8, w = 8, x = 16, y = 44 }
          targets         = [{ datasource = local.prometheus, expr = "min by (target) ((probe_ssl_earliest_cert_expiry - time()) / 86400)", format = "table", instant = true, refId = "A" }]
          title           = "TLS certificate days left"
          transformations = local.table_transformations
        }
      },
    ],
    # The logs row, only with a Loki datasource.
    slice([
      { kind = "row", panel = { gridPos = { h = 1, w = 24, x = 0, y = 52 }, title = "Logs" } },
      {
        kind = "logs"
        panel = {
          gridPos = { h = 12, w = 24, x = 0, y = 53 }
          targets = [{
            datasource = local.loki
            expr       = "{cluster=\"${var.cluster_name}\", ${local.ns}} |~ \"(?i)(error|panic|fatal|exception)\""
            refId      = "A"
          }]
          title = "Errors in logs"
        }
      },
    ], 0, local.loki == null ? 0 : 2),
  )

  prometheus = { type = "prometheus", uid = var.prometheus_datasource_uid }

  # Stats where 0 is healthy: green at 0, red above.
  stat_thresholds_zero_good = {
    defaults = {
      decimals   = 0
      thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "red", value = 1 }] }
      unit       = "none"
    }
    overrides = []
  }

  # Tables show one row per series: drop the time column, keep labels.
  table_transformations = [
    { id = "labelsToFields", options = { mode = "columns" } },
    { id = "organize", options = { excludeByName = { Time = true } } },
  ]
}
