# Service-level (APM) rules, on when var.apm.enabled. Grafana reads a
# request-duration histogram, so every service needs request metrics: an
# OpenTelemetry SDK, a Prometheus client library, a service mesh or an
# ingress controller. Datadog reads the trace metrics of APM. Metric and label
# names come from var.apm through these placeholders:
#
#   __M__      histogram base name (the _bucket, _count and _sum series)
#   __S__      service label
#   __R__      route label
#   __C__      status code label
#   __ASEL__   var.apm.scope, in the forms {__ASEL__} and ,__ASEL__}
#   __SPAN__   trace metric span name: trace.<span>.hits, trace.<span>.errors,
#              and the trace.<span> latency distribution, in seconds
#   __APM__    var.apm.scope, or * for every service
#   __FLOOR__  minimum requests per second for a rule to judge a service, so
#              a handful of requests can't produce a 100% error rate. Datadog's
#              cutoff_min() turns lower rates into gaps.
#
# Datadog counts a server span as an error on 5xx, not 4xx, which matches the
# 5xx filter in the Grafana rules.
locals {
  apm_rules = {
    endpoint_error_rate_high = {
      datadog = {
        query   = "avg(__WINDOW__):100 * sum:trace.__SPAN__.errors{__APM__} by {service,resource_name}.as_rate() / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service,resource_name}.as_rate(), __FLOOR__)"
        summary = "{{value}}% of requests to {{resource_name.name}} on {{service.name}} are failing, even if the service's overall error rate looks fine."
        window  = "last_5m"
      }
      grafana = {
        expr           = "100 * sum by (__S__, __R__) (rate(__M___count{__C__=~\"5..\",__ASEL__}[5m])) / sum by (__S__, __R__) (rate(__M___count{__ASEL__}[5m])) and on (__S__, __R__) sum by (__S__, __R__) (rate(__M___count{__ASEL__}[5m])) >= __FLOOR__"
        pending_period = "5m"
        subject        = "{{ index $labels \"__S__\" }} {{ index $labels \"__R__\" }}"
        summary        = "{{ humanize $values.A.Value }}% of requests to {{ index $labels \"__R__\" }} on {{ index $labels \"__S__\" }} are failing with 5xx, even if the service's overall error rate looks fine."
      }
      group     = "apm"
      operator  = "gt"
      requires  = "apm"
      severity  = "warning"
      threshold = var.apm.error_rate_percent
      title     = "Endpoint error rate high"
    }
    service_error_rate_high = {
      datadog = {
        query   = "avg(__WINDOW__):100 * sum:trace.__SPAN__.errors{__APM__} by {service}.as_rate() / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__)"
        summary = "{{value}}% of requests to {{service.name}} are failing."
        window  = "last_5m"
      }
      grafana = {
        expr           = "100 * sum by (__S__) (rate(__M___count{__C__=~\"5..\",__ASEL__}[5m])) / sum by (__S__) (rate(__M___count{__ASEL__}[5m])) and on (__S__) sum by (__S__) (rate(__M___count{__ASEL__}[5m])) >= __FLOOR__"
        pending_period = "5m"
        subject        = "{{ index $labels \"__S__\" }}"
        summary        = "{{ humanize $values.A.Value }}% of requests to {{ index $labels \"__S__\" }} are failing with 5xx."
      }
      group     = "apm"
      operator  = "gt"
      requires  = "apm"
      severity  = "critical"
      threshold = var.apm.error_rate_percent
      title     = "Service error rate high"
    }
    service_errors_after_deploy = {
      # Datadog tags each deploy with the service's `version`. The last factor
      # is 1 for a version that had no traffic 30 minutes ago, and 0 otherwise,
      # so only versions rolled out in the last 30 minutes can fire.
      datadog = {
        query   = "avg(__WINDOW__):100 * sum:trace.__SPAN__.errors{__APM__} by {service,version}.as_rate() / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service,version}.as_rate(), __FLOOR__) * (1 - clamp_max(default_zero(timeshift(sum:trace.__SPAN__.hits{__APM__} by {service,version}.as_rate(), -1800)) * 1000000, 1))"
        summary = "{{service.name}} version {{version.name}}, rolled out in the last 30 minutes, is failing {{value}}% of requests. Check whether the release caused it."
        window  = "last_2m"
      }
      grafana = {
        expr           = "100 * sum by (__S__, namespace) (rate(__M___count{__C__=~\"5..\",__ASEL__}[5m])) / sum by (__S__, namespace) (rate(__M___count{__ASEL__}[5m])) and on (namespace) max by (namespace) (changes(kube_deployment_status_observed_generation[30m])) > 0"
        pending_period = "2m"
        subject        = "{{ index $labels \"__S__\" }} in {{ $labels.namespace }}"
        summary        = "{{ index $labels \"__S__\" }} is failing {{ humanize $values.A.Value }}% of requests, and a deployment in {{ $labels.namespace }} rolled out in the last 30 minutes. Check whether the release caused it."
      }
      group     = "apm"
      operator  = "gt"
      requires  = "apm"
      severity  = "warning"
      threshold = var.apm.deploy_error_rate_percent
      title     = "Errors after a deploy"
    }
    service_latency_avg_high = {
      # Multiplying by floor / floor keeps the latency where traffic is above
      # the floor and leaves a gap where it isn't.
      datadog = {
        query   = "avg(__WINDOW__):avg:trace.__SPAN__{__APM__} by {service} * cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__) / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__)"
        summary = "{{service.name}} is averaging {{value}}s per request."
        window  = "last_10m"
      }
      grafana = {
        expr           = "sum by (__S__) (rate(__M___sum{__ASEL__}[5m])) / sum by (__S__) (rate(__M___count{__ASEL__}[5m])) and on (__S__) sum by (__S__) (rate(__M___count{__ASEL__}[5m])) >= __FLOOR__"
        pending_period = "10m"
        subject        = "{{ index $labels \"__S__\" }}"
        summary        = "{{ index $labels \"__S__\" }} is averaging {{ humanizeDuration $values.A.Value }} per request."
      }
      group     = "apm"
      operator  = "gt"
      requires  = "apm"
      severity  = "warning"
      threshold = var.apm.latency_avg_seconds
      title     = "Service average latency high"
    }
    service_latency_p90_high = {
      datadog = {
        query   = "avg(__WINDOW__):p90:trace.__SPAN__{__APM__} by {service} * cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__) / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__)"
        summary = "90% of requests to {{service.name}} take up to {{value}}s."
        window  = "last_10m"
      }
      grafana = {
        expr           = "histogram_quantile(0.9, sum by (__S__, le) (rate(__M___bucket{__ASEL__}[5m]))) and on (__S__) sum by (__S__) (rate(__M___count{__ASEL__}[5m])) >= __FLOOR__"
        pending_period = "10m"
        subject        = "{{ index $labels \"__S__\" }}"
        summary        = "90% of requests to {{ index $labels \"__S__\" }} take up to {{ humanizeDuration $values.A.Value }}."
      }
      group     = "apm"
      operator  = "gt"
      requires  = "apm"
      severity  = "warning"
      threshold = var.apm.latency_p90_seconds
      title     = "Service p90 latency high"
    }
    service_traffic_drop = {
      # Compares traffic with the same time an hour earlier. modules/alerts
      # compares with the last hour's average, which Datadog monitors can't
      # express. A service that stops reporting entirely has no data and stays
      # quiet, so pair this with synthetic checks.
      datadog = {
        query   = "avg(__WINDOW__):100 * sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate() / cutoff_min(hour_before(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate()), __FLOOR__)"
        summary = "{{service.name}} is getting {{value}}% of the traffic it had an hour ago."
        window  = "last_10m"
      }
      # Catches silent outages, where requests stop rather than fail. A service
      # whose metrics vanish entirely has no data and stays quiet, so pair this
      # with synthetic checks.
      grafana = {
        expr           = "100 * sum by (__S__) (rate(__M___count{__ASEL__}[5m])) / sum by (__S__) (rate(__M___count{__ASEL__}[1h])) and on (__S__) sum by (__S__) (rate(__M___count{__ASEL__}[1h])) >= __FLOOR__"
        pending_period = "10m"
        subject        = "{{ index $labels \"__S__\" }}"
        summary        = "{{ index $labels \"__S__\" }} is getting {{ humanize $values.A.Value }}% of its usual traffic over the last hour."
      }
      group     = "apm"
      operator  = "lt"
      requires  = "apm"
      severity  = "warning"
      threshold = 100 - var.apm.traffic_drop_percent
      title     = "Service traffic dropped"
    }
  }
}
