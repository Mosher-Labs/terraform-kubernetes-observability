locals {
  # APM settings rendered into PromQL: the service label, and the matcher
  # lists for all requests and for 5xx responses.
  apm_s       = var.apm.service_label
  apm_sel     = var.apm.selector == "" ? "" : "{${var.apm.selector}}"
  apm_sel_5xx = "{${var.apm.status_label}=~\"5..\"${var.apm.selector == "" ? "" : ",${var.apm.selector}"}}"

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
    # The Services row, only with APM metrics. Grafana closes up the gap when
    # there's no logs row above it.
    slice([
      { kind = "row", panel = { gridPos = { h = 1, w = 24, x = 0, y = 65 }, title = "Services" } },
      {
        kind = "timeseries"
        panel = {
          fieldConfig = { defaults = { unit = "reqps" }, overrides = [] }
          gridPos     = { h = 8, w = 8, x = 0, y = 66 }
          targets     = [{ datasource = local.prometheus, expr = "sum by (${local.apm_s}) (rate(${var.apm.metric}_count${local.apm_sel}[5m]))", legendFormat = "{{${local.apm_s}}}", range = true, refId = "A" }]
          title       = "Requests per second"
        }
      },
      {
        kind = "timeseries"
        panel = {
          fieldConfig = { defaults = { min = 0, unit = "percent" }, overrides = [] }
          gridPos     = { h = 8, w = 8, x = 8, y = 66 }
          targets     = [{ datasource = local.prometheus, expr = "100 * sum by (${local.apm_s}) (rate(${var.apm.metric}_count${local.apm_sel_5xx}[5m])) / sum by (${local.apm_s}) (rate(${var.apm.metric}_count${local.apm_sel}[5m]))", legendFormat = "{{${local.apm_s}}}", range = true, refId = "A" }]
          title       = "5xx error rate"
        }
      },
      {
        kind = "timeseries"
        panel = {
          fieldConfig = { defaults = { unit = "s" }, overrides = [] }
          gridPos     = { h = 8, w = 8, x = 16, y = 66 }
          targets     = [{ datasource = local.prometheus, expr = "histogram_quantile(0.9, sum by (${local.apm_s}, le) (rate(${var.apm.metric}_bucket${local.apm_sel}[5m])))", legendFormat = "{{${local.apm_s}}}", range = true, refId = "A" }]
          title       = "p90 latency"
        }
      },
      {
        kind = "table"
        panel = {
          fieldConfig     = { defaults = { decimals = 3, unit = "s" }, overrides = [] }
          gridPos         = { h = 8, w = 24, x = 0, y = 74 }
          targets         = [{ datasource = local.prometheus, expr = "topk(10, histogram_quantile(0.9, sum by (${local.apm_s}, ${var.apm.route_label}, le) (rate(${var.apm.metric}_bucket${local.apm_sel}[5m]))))", format = "table", instant = true, refId = "A" }]
          title           = "Slowest routes, p90"
          transformations = local.table_transformations
        }
      },
    ], 0, var.apm.enabled ? 5 : 0),
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
    # One row per SLO, the same numbers the burn-rate alerts act on.
    flatten([
      for i, id in sort(keys(var.slos)) : [
        { kind = "row", panel = { gridPos = { h = 1, w = 24, x = 0, y = 100 + i * 9 }, title = "SLO: ${var.slos[id].title} (${format("%g", var.slos[id].target * 100)}% over ${var.slos[id].window_days}d)" } },
        {
          kind = "stat"
          panel = {
            fieldConfig = {
              defaults = {
                decimals   = 3
                thresholds = { mode = "absolute", steps = [{ color = "red", value = null }, { color = "green", value = var.slos[id].target }] }
                unit       = "percentunit"
              }
              overrides = []
            }
            gridPos = { h = 8, w = 4, x = 0, y = 101 + i * 9 }
            targets = [{ datasource = local.prometheus, expr = var.slos[id].sli, instant = true, legendFormat = "", refId = "A" }]
            title   = "SLI (${var.slos[id].window_days}d)"
          }
        },
        {
          kind = "stat"
          panel = {
            fieldConfig = {
              defaults = {
                decimals   = 1
                thresholds = { mode = "absolute", steps = [{ color = "red", value = null }, { color = "orange", value = 0.25 }, { color = "green", value = 0.5 }] }
                unit       = "percentunit"
              }
              overrides = []
            }
            gridPos = { h = 8, w = 4, x = 4, y = 101 + i * 9 }
            targets = [{ datasource = local.prometheus, expr = var.slos[id].budget_remaining, instant = true, legendFormat = "", refId = "A" }]
            title   = "Error budget left"
          }
        },
        {
          kind = "timeseries"
          panel = {
            fieldConfig = {
              defaults = {
                custom     = { thresholdsStyle = { mode = "line" } }
                thresholds = { mode = "absolute", steps = [{ color = "transparent", value = null }, { color = "red", value = 14.4 }] }
                unit       = "none"
              }
              overrides = []
            }
            gridPos = { h = 8, w = 16, x = 8, y = 101 + i * 9 }
            targets = [for j, w in sort(keys(var.slos[id].burn_rates)) : { datasource = local.prometheus, expr = var.slos[id].burn_rates[w], legendFormat = "burn rate ${w}", range = true, refId = substr("ABC", j, 1) }]
            title   = "Burn rate (1 uses the budget exactly over the window; fast alerts at 14.4)"
          }
        },
      ]
    ]),
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
