# Service-level (APM) rules, created when var.apm.enabled. They read a
# request-duration histogram, so every service needs request metrics: an
# OpenTelemetry SDK, a Prometheus client library, a service mesh or an
# ingress controller. Metric and label names come from var.apm through these
# placeholders:
#
#   __M__      histogram base name (the _bucket, _count and _sum series)
#   __S__      service label
#   __R__      route label
#   __C__      status code label
#   __ASEL__   extra matchers from var.apm.selector, in the forms {__ASEL__}
#              and ,__ASEL__}
#   __FLOOR__  minimum requests per second for a rule to judge a service, so
#              a handful of requests can't produce a 100% error rate
locals {
  apm_catalog_raw = {
    endpoint_error_rate_high = {
      expr           = "100 * sum by (__S__, __R__) (rate(__M___count{__C__=~\"5..\",__ASEL__}[5m])) / sum by (__S__, __R__) (rate(__M___count{__ASEL__}[5m])) and on (__S__, __R__) sum by (__S__, __R__) (rate(__M___count{__ASEL__}[5m])) >= __FLOOR__"
      group          = "apm"
      operator       = "gt"
      pending_period = "5m"
      severity       = "warning"
      subject        = "{{ index $labels \"__S__\" }} {{ index $labels \"__R__\" }}"
      summary        = "{{ humanize $values.A.Value }}% of requests to {{ index $labels \"__R__\" }} on {{ index $labels \"__S__\" }} are failing with 5xx, even if the service's overall error rate looks fine."
      threshold      = var.apm.error_rate_percent
      title          = "Endpoint error rate high"
    }
    service_error_rate_high = {
      expr           = "100 * sum by (__S__) (rate(__M___count{__C__=~\"5..\",__ASEL__}[5m])) / sum by (__S__) (rate(__M___count{__ASEL__}[5m])) and on (__S__) sum by (__S__) (rate(__M___count{__ASEL__}[5m])) >= __FLOOR__"
      group          = "apm"
      operator       = "gt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "{{ index $labels \"__S__\" }}"
      summary        = "{{ humanize $values.A.Value }}% of requests to {{ index $labels \"__S__\" }} are failing with 5xx."
      threshold      = var.apm.error_rate_percent
      title          = "Service error rate high"
    }
    service_errors_after_deploy = {
      expr           = "100 * sum by (__S__, namespace) (rate(__M___count{__C__=~\"5..\",__ASEL__}[5m])) / sum by (__S__, namespace) (rate(__M___count{__ASEL__}[5m])) and on (namespace) max by (namespace) (changes(kube_deployment_status_observed_generation[30m])) > 0"
      group          = "apm"
      operator       = "gt"
      pending_period = "2m"
      severity       = "warning"
      subject        = "{{ index $labels \"__S__\" }} in {{ $labels.namespace }}"
      summary        = "{{ index $labels \"__S__\" }} is failing {{ humanize $values.A.Value }}% of requests, and a deployment in {{ $labels.namespace }} rolled out in the last 30 minutes. Check whether the release caused it."
      threshold      = var.apm.deploy_error_rate_percent
      title          = "Errors after a deploy"
    }
    service_latency_avg_high = {
      expr           = "sum by (__S__) (rate(__M___sum{__ASEL__}[5m])) / sum by (__S__) (rate(__M___count{__ASEL__}[5m])) and on (__S__) sum by (__S__) (rate(__M___count{__ASEL__}[5m])) >= __FLOOR__"
      group          = "apm"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ index $labels \"__S__\" }}"
      summary        = "{{ index $labels \"__S__\" }} is averaging {{ humanizeDuration $values.A.Value }} per request."
      threshold      = var.apm.latency_avg_seconds
      title          = "Service average latency high"
    }
    service_latency_p90_high = {
      expr           = "histogram_quantile(0.9, sum by (__S__, le) (rate(__M___bucket{__ASEL__}[5m]))) and on (__S__) sum by (__S__) (rate(__M___count{__ASEL__}[5m])) >= __FLOOR__"
      group          = "apm"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ index $labels \"__S__\" }}"
      summary        = "90% of requests to {{ index $labels \"__S__\" }} take up to {{ humanizeDuration $values.A.Value }}."
      threshold      = var.apm.latency_p90_seconds
      title          = "Service p90 latency high"
    }
    # Catches silent outages, where requests stop rather than fail. A service
    # whose metrics vanish entirely has no data and stays quiet, so pair this
    # with synthetic checks.
    service_traffic_drop = {
      expr           = "100 * sum by (__S__) (rate(__M___count{__ASEL__}[5m])) / sum by (__S__) (rate(__M___count{__ASEL__}[1h])) and on (__S__) sum by (__S__) (rate(__M___count{__ASEL__}[1h])) >= __FLOOR__"
      group          = "apm"
      operator       = "lt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ index $labels \"__S__\" }}"
      summary        = "{{ index $labels \"__S__\" }} is getting {{ humanize $values.A.Value }}% of its usual traffic over the last hour."
      threshold      = 100 - var.apm.traffic_drop_percent
      title          = "Service traffic dropped"
    }
  }

  apm_catalog = {
    for id, r in local.apm_catalog_raw : id => merge(r, {
      for field in ["expr", "subject", "summary"] : field => replace(replace(replace(replace(replace(replace(replace(r[field],
        "__M__", var.apm.metric),
        "__S__", var.apm.service_label),
        "__R__", var.apm.route_label),
        "__C__", var.apm.status_label),
        "__FLOOR__", tostring(var.apm.min_requests_per_second)),
        ",__ASEL__}", var.apm.selector == "" ? "}" : ",${var.apm.selector}}"),
        "{__ASEL__}", var.apm.selector == "" ? "" : "{${var.apm.selector}}",
      )
    })
  }
}
