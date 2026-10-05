# Service-level (APM) rules from Datadog APM trace metrics, created when
# var.apm.enabled. Same rule IDs and thresholds as modules/alerts'
# catalog_apm.tf. Placeholders:
#
#   __SPAN__   trace metric span name, var.apm.span_name: trace.<span>.hits,
#              trace.<span>.errors, and the trace.<span> latency
#              distribution, in seconds
#   __APM__    var.apm.scope, or * for every service
#   __FLOOR__  minimum requests per second for a rule to judge a service.
#              cutoff_min() turns lower rates into gaps, so the ratio has no
#              value instead of a 100% error rate from a handful of requests.
#
# Datadog counts a server span as an error on 5xx, not 4xx, which matches the
# Grafana rules' 5xx filter.
locals {
  apm_catalog_raw = {
    endpoint_error_rate_high = {
      operator  = "gt"
      query     = "avg(__WINDOW__):100 * sum:trace.__SPAN__.errors{__APM__} by {service,resource_name}.as_rate() / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service,resource_name}.as_rate(), __FLOOR__)"
      severity  = "warning"
      summary   = "{{value}}% of requests to {{resource_name.name}} on {{service.name}} are failing, even if the service's overall error rate looks fine."
      threshold = var.apm.error_rate_percent
      title     = "Endpoint error rate high"
      window    = "last_5m"
    }
    service_error_rate_high = {
      operator  = "gt"
      query     = "avg(__WINDOW__):100 * sum:trace.__SPAN__.errors{__APM__} by {service}.as_rate() / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__)"
      severity  = "critical"
      summary   = "{{value}}% of requests to {{service.name}} are failing."
      threshold = var.apm.error_rate_percent
      title     = "Service error rate high"
      window    = "last_5m"
    }
    # Datadog tags each deploy with the service's `version`. The last factor
    # is 1 for a version that had no traffic 30 minutes ago, and 0 otherwise,
    # so only versions rolled out in the last 30 minutes can fire.
    service_errors_after_deploy = {
      operator  = "gt"
      query     = "avg(__WINDOW__):100 * sum:trace.__SPAN__.errors{__APM__} by {service,version}.as_rate() / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service,version}.as_rate(), __FLOOR__) * (1 - clamp_max(default_zero(timeshift(sum:trace.__SPAN__.hits{__APM__} by {service,version}.as_rate(), -1800)) * 1000000, 1))"
      severity  = "warning"
      summary   = "{{service.name}} version {{version.name}}, rolled out in the last 30 minutes, is failing {{value}}% of requests. Check whether the release caused it."
      threshold = var.apm.deploy_error_rate_percent
      title     = "Errors after a deploy"
      window    = "last_2m"
    }
    # Multiplying by floor / floor keeps the latency where traffic is above
    # the floor and leaves a gap where it isn't.
    service_latency_avg_high = {
      operator  = "gt"
      query     = "avg(__WINDOW__):avg:trace.__SPAN__{__APM__} by {service} * cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__) / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__)"
      severity  = "warning"
      summary   = "{{service.name}} is averaging {{value}}s per request."
      threshold = var.apm.latency_avg_seconds
      title     = "Service average latency high"
      window    = "last_10m"
    }
    service_latency_p90_high = {
      operator  = "gt"
      query     = "avg(__WINDOW__):p90:trace.__SPAN__{__APM__} by {service} * cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__) / cutoff_min(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate(), __FLOOR__)"
      severity  = "warning"
      summary   = "90% of requests to {{service.name}} take up to {{value}}s."
      threshold = var.apm.latency_p90_seconds
      title     = "Service p90 latency high"
      window    = "last_10m"
    }
    # Compares traffic with the same time an hour earlier. modules/alerts
    # compares with the last hour's average, which Datadog monitors can't
    # express. A service that stops reporting entirely has no data and stays
    # quiet, so pair this with synthetic checks.
    service_traffic_drop = {
      operator  = "lt"
      query     = "avg(__WINDOW__):100 * sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate() / cutoff_min(hour_before(sum:trace.__SPAN__.hits{__APM__} by {service}.as_rate()), __FLOOR__)"
      severity  = "warning"
      summary   = "{{service.name}} is getting {{value}}% of the traffic it had an hour ago."
      threshold = 100 - var.apm.traffic_drop_percent
      title     = "Service traffic dropped"
      window    = "last_10m"
    }
  }

  apm_catalog = {
    for id, r in local.apm_catalog_raw : id => merge(r, {
      group = "apm"
      query = replace(replace(replace(r.query,
        "__SPAN__", var.apm.span_name),
        "__APM__", var.apm.scope == "" ? "*" : var.apm.scope),
        "__FLOOR__", tostring(var.apm.min_requests_per_second),
      )
      requires = "apm"
    })
  }
}
