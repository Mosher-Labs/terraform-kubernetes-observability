# Service-level (APM) rules, on when var.apm.enabled. Grafana reads a
# request-duration histogram, so every service needs request metrics: an
# OpenTelemetry SDK, a Prometheus client library, a service mesh or an
# ingress controller. Datadog reads the trace metrics of APM. Metric and label
# names come from var.apm through these template variables:
#
#   ${metric}         histogram base name (the _bucket, _count and _sum series)
#   ${service_label}  service label
#   ${route_label}    route label
#   ${status_label}   status code label
#   ${asel}           var.apm.scope as {scope}, or nothing; ${asel_more} is
#                     ,scope for use inside braces that already have a matcher
#   ${span}           trace metric span name: trace.<span>.hits,
#                     trace.<span>.errors, and the trace.<span> latency
#                     distribution, in seconds
#   ${apm_scope}      var.apm.scope, or * for every service
#   ${floor}          minimum requests per second for a rule to judge a
#                     service, so a handful of requests can't produce a 100%
#                     error rate. Datadog's cutoff_min() turns lower rates
#                     into gaps.
#
# Datadog counts a server span as an error on 5xx, not 4xx, which matches the
# 5xx filter in the Grafana rules.
locals {
  apm_rules = {
    endpoint_error_rate_high = {
      datadog = {
        query   = "avg($${window}):100 * sum:trace.$${span}.errors{$${apm_scope}} by {service,resource_name}.as_rate() / cutoff_min(sum:trace.$${span}.hits{$${apm_scope}} by {service,resource_name}.as_rate(), $${floor})"
        summary = "{{value}}% of requests to {{resource_name.name}} on {{service.name}} are failing, even if the service's overall error rate looks fine."
        window  = "last_5m"
      }
      grafana = {
        expr           = "100 * sum by ($${service_label}, $${route_label}) (rate($${metric}_count{$${status_label}=~\"5..\"$${asel_more}}[5m])) / sum by ($${service_label}, $${route_label}) (rate($${metric}_count$${asel}[5m])) and on ($${service_label}, $${route_label}) sum by ($${service_label}, $${route_label}) (rate($${metric}_count$${asel}[5m])) >= $${floor}"
        pending_period = "5m"
        subject        = "{{ index $labels \"$${service_label}\" }} {{ index $labels \"$${route_label}\" }}"
        summary        = "{{ humanize $values.A.Value }}% of requests to {{ index $labels \"$${route_label}\" }} on {{ index $labels \"$${service_label}\" }} are failing with 5xx, even if the service's overall error rate looks fine."
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
        query   = "avg($${window}):100 * sum:trace.$${span}.errors{$${apm_scope}} by {service}.as_rate() / cutoff_min(sum:trace.$${span}.hits{$${apm_scope}} by {service}.as_rate(), $${floor})"
        summary = "{{value}}% of requests to {{service.name}} are failing."
        window  = "last_5m"
      }
      grafana = {
        expr           = "100 * sum by ($${service_label}) (rate($${metric}_count{$${status_label}=~\"5..\"$${asel_more}}[5m])) / sum by ($${service_label}) (rate($${metric}_count$${asel}[5m])) and on ($${service_label}) sum by ($${service_label}) (rate($${metric}_count$${asel}[5m])) >= $${floor}"
        pending_period = "5m"
        subject        = "{{ index $labels \"$${service_label}\" }}"
        summary        = "{{ humanize $values.A.Value }}% of requests to {{ index $labels \"$${service_label}\" }} are failing with 5xx."
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
        query   = "avg($${window}):100 * sum:trace.$${span}.errors{$${apm_scope}} by {service,version}.as_rate() / cutoff_min(sum:trace.$${span}.hits{$${apm_scope}} by {service,version}.as_rate(), $${floor}) * (1 - clamp_max(default_zero(timeshift(sum:trace.$${span}.hits{$${apm_scope}} by {service,version}.as_rate(), -1800)) * 1000000, 1))"
        summary = "{{service.name}} version {{version.name}}, rolled out in the last 30 minutes, is failing {{value}}% of requests. Check whether the release caused it."
        window  = "last_2m"
      }
      grafana = {
        expr           = "100 * sum by ($${service_label}, namespace) (rate($${metric}_count{$${status_label}=~\"5..\"$${asel_more}}[5m])) / sum by ($${service_label}, namespace) (rate($${metric}_count$${asel}[5m])) and on (namespace) max by (namespace) (changes(kube_deployment_status_observed_generation[30m])) > 0"
        pending_period = "2m"
        subject        = "{{ index $labels \"$${service_label}\" }} in {{ $labels.namespace }}"
        summary        = "{{ index $labels \"$${service_label}\" }} is failing {{ humanize $values.A.Value }}% of requests, and a deployment in {{ $labels.namespace }} rolled out in the last 30 minutes. Check whether the release caused it."
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
        query   = "avg($${window}):avg:trace.$${span}{$${apm_scope}} by {service} * cutoff_min(sum:trace.$${span}.hits{$${apm_scope}} by {service}.as_rate(), $${floor}) / cutoff_min(sum:trace.$${span}.hits{$${apm_scope}} by {service}.as_rate(), $${floor})"
        summary = "{{service.name}} is averaging {{value}}s per request."
        window  = "last_10m"
      }
      grafana = {
        expr           = "sum by ($${service_label}) (rate($${metric}_sum$${asel}[5m])) / sum by ($${service_label}) (rate($${metric}_count$${asel}[5m])) and on ($${service_label}) sum by ($${service_label}) (rate($${metric}_count$${asel}[5m])) >= $${floor}"
        pending_period = "10m"
        subject        = "{{ index $labels \"$${service_label}\" }}"
        summary        = "{{ index $labels \"$${service_label}\" }} is averaging {{ humanizeDuration $values.A.Value }} per request."
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
        query   = "avg($${window}):p90:trace.$${span}{$${apm_scope}} by {service} * cutoff_min(sum:trace.$${span}.hits{$${apm_scope}} by {service}.as_rate(), $${floor}) / cutoff_min(sum:trace.$${span}.hits{$${apm_scope}} by {service}.as_rate(), $${floor})"
        summary = "90% of requests to {{service.name}} take up to {{value}}s."
        window  = "last_10m"
      }
      grafana = {
        expr           = "histogram_quantile(0.9, sum by ($${service_label}, le) (rate($${metric}_bucket$${asel}[5m]))) and on ($${service_label}) sum by ($${service_label}) (rate($${metric}_count$${asel}[5m])) >= $${floor}"
        pending_period = "10m"
        subject        = "{{ index $labels \"$${service_label}\" }}"
        summary        = "90% of requests to {{ index $labels \"$${service_label}\" }} take up to {{ humanizeDuration $values.A.Value }}."
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
        query   = "avg($${window}):100 * sum:trace.$${span}.hits{$${apm_scope}} by {service}.as_rate() / cutoff_min(hour_before(sum:trace.$${span}.hits{$${apm_scope}} by {service}.as_rate()), $${floor})"
        summary = "{{service.name}} is getting {{value}}% of the traffic it had an hour ago."
        window  = "last_10m"
      }
      # Catches silent outages, where requests stop rather than fail. A service
      # whose metrics vanish entirely has no data and stays quiet, so pair this
      # with synthetic checks.
      grafana = {
        expr           = "100 * sum by ($${service_label}) (rate($${metric}_count$${asel}[5m])) / sum by ($${service_label}) (rate($${metric}_count$${asel}[1h])) and on ($${service_label}) sum by ($${service_label}) (rate($${metric}_count$${asel}[1h])) >= $${floor}"
        pending_period = "10m"
        subject        = "{{ index $labels \"$${service_label}\" }}"
        summary        = "{{ index $labels \"$${service_label}\" }} is getting {{ humanize $values.A.Value }}% of its usual traffic over the last hour."
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
